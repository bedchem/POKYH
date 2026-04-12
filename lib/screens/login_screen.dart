import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:local_auth/local_auth.dart';

import '../services/webuntis_service.dart';
import '../theme/app_theme.dart';
import '../services/secure_credential_service.dart';
import 'home_screen.dart';

const int _kMaxBiometricAttempts = 3;
const Duration _kLockoutDuration = Duration(minutes: 5);

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _service = WebUntisService();
  final _credService = SecureCredentialService();
  final _localAuth = LocalAuthentication();
  final _focusUser = FocusNode();
  final _focusPass = FocusNode();

  bool _loading = false;
  bool _obscure = true;
  bool _saveLogin = false;
  String? _error;

  List<SavedAccount> _savedAccounts = [];
  List<BiometricType> _availableBiometrics = [];

  final Map<String, int> _failedAttempts = {};
  final Map<String, DateTime> _lockoutUntil = {};

  late final AnimationController _anim;
  late final Animation<double> _fade;

  // ──────────────────────────────────────────────────────────────────────────
  // PLATTFORM-HELPER
  // ──────────────────────────────────────────────────────────────────────────

  /// Auf Android müssen System-Dialoge aktiv bleiben (useErrorDialogs: true),
  /// damit der BiometricPrompt korrekt angezeigt wird.
  /// Auf iOS übernimmt das System den Dialog selbst – false verhindert
  /// doppelte Dialoge beim LAContext.
  bool get _useErrorDialogs => Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _anim.forward();
    _init();
  }

  Future<void> _init() async {
    try {
      await _loadSavedAccounts();
      await _detectBiometrics();
    } catch (_) {}
  }

  @override
  void dispose() {
    _anim.dispose();
    _userCtrl.dispose();
    _passCtrl.dispose();
    _focusUser.dispose();
    _focusPass.dispose();
    super.dispose();
  }

  // ──────────────────────────────────────────────────────────────────────────
  // BIOMETRIE ERKENNEN
  // iOS:     BiometricType.face / BiometricType.fingerprint
  // Android: BiometricType.fingerprint / BiometricType.strong (API 30+)
  //          / BiometricType.weak / BiometricType.iris (Samsung)
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _detectBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!canCheck) {
        if (mounted) setState(() => _availableBiometrics = []);
        return;
      }

      final biometrics = await _localAuth.getAvailableBiometrics();
      if (mounted) setState(() => _availableBiometrics = biometrics);
    } catch (_) {
      if (mounted) setState(() => _availableBiometrics = []);
    }
  }

  // Face ID (iOS) oder Gesichtserkennung (Android – z. B. BiometricType.face)
  bool get _hasFaceId =>
      _availableBiometrics.contains(BiometricType.face) ||
      _availableBiometrics.contains(BiometricType.iris); // Samsung iris

  // Fingerabdruck auf iOS & Android (fingerprint, strong, weak)
  bool get _hasFingerprint =>
      _availableBiometrics.contains(BiometricType.fingerprint) ||
      _availableBiometrics.contains(BiometricType.strong) || // Android API 30+
      _availableBiometrics.contains(BiometricType.weak); // Android API 30+

  bool get _hasAnyBiometric => _hasFaceId || _hasFingerprint;

  IconData get _bestBiometricIcon {
    if (_hasFaceId) return Icons.face;
    if (_hasFingerprint) return Icons.fingerprint;
    return Icons.lock_outline;
  }

  String get _bestBiometricLabel {
    if (_hasFaceId) {
      // Auf Android heißt es i. d. R. "Gesichtserkennung", auf iOS "Face ID"
      return Platform.isIOS ? 'Face ID' : 'Gesichtserkennung';
    }
    if (_hasFingerprint) {
      return Platform.isIOS ? 'Fingerabdruck' : 'Fingerabdruck';
    }
    return 'Biometrie';
  }

  // ──────────────────────────────────────────────────────────────────────────
  // LOCKOUT
  // ──────────────────────────────────────────────────────────────────────────

  bool _isLockedOut(String username) {
    final until = _lockoutUntil[username];
    if (until == null) return false;
    if (DateTime.now().isAfter(until)) {
      _lockoutUntil.remove(username);
      _failedAttempts.remove(username);
      return false;
    }
    return true;
  }

  String _lockoutMessage(String username) {
    final until = _lockoutUntil[username];
    if (until == null) return '';
    final remaining = until.difference(DateTime.now());
    final mins = remaining.inMinutes;
    final secs = remaining.inSeconds % 60;
    return 'Zu viele Fehlversuche. Bitte in ${mins}m ${secs}s erneut versuchen.';
  }

  void _recordFailedAttempt(String username) {
    final count = (_failedAttempts[username] ?? 0) + 1;
    _failedAttempts[username] = count;
    if (count >= _kMaxBiometricAttempts) {
      _lockoutUntil[username] = DateTime.now().add(_kLockoutDuration);
      _failedAttempts.remove(username);
    }
  }

  void _clearFailedAttempts(String username) {
    _failedAttempts.remove(username);
    _lockoutUntil.remove(username);
  }

  // ──────────────────────────────────────────────────────────────────────────
  // BIOMETRISCHER LOGIN
  // iOS:     LAContext → Face ID / Touch ID → Passcode-Fallback
  // Android: BiometricPrompt → Geräte-PIN-Fallback
  //          WICHTIG: useErrorDialogs muss auf Android true sein,
  //          sonst erscheint der BiometricPrompt nie.
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _biometricLogin(SavedAccount account) async {
    if (_loading) return;
    if (!mounted) return;

    // Lockout-Prüfung
    if (_isLockedOut(account.username)) {
      _setError(_lockoutMessage(account.username));
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1. Prüfen ob Biometrie grundsätzlich möglich ist
      bool canCheck = false;
      try {
        canCheck = await _localAuth.canCheckBiometrics;
      } catch (_) {
        canCheck = false;
      }

      if (!canCheck) {
        _setError('Biometrie nicht verfügbar. Bitte manuell anmelden.');
        return;
      }

      // 2. Geräte-Unterstützung prüfen
      bool isSupported = false;
      try {
        isSupported = await _localAuth.isDeviceSupported();
      } catch (_) {
        isSupported = false;
      }

      if (!isSupported) {
        _setError('Gerätesicherheit nicht unterstützt.');
        return;
      }

      bool authenticated = false;

      // 3. Primär: Biometrie (biometricOnly = true)
      //    iOS:     Face ID / Touch ID – useErrorDialogs false (System übernimmt)
      //    Android: BiometricPrompt    – useErrorDialogs true  (Plugin übernimmt)
      if (_hasAnyBiometric) {
        try {
          authenticated = await _localAuth.authenticate(
            localizedReason: _biometricReason(account.username),
            options: AuthenticationOptions(
              biometricOnly: true,
              stickyAuth: true,
              useErrorDialogs: _useErrorDialogs, // false=iOS, true=Android
              sensitiveTransaction: true,
            ),
          );
        } catch (e) {
          // Nutzer hat abgebrochen oder Sensorfehler →
          // nur bei echtem Sensorfehler zum PIN-Fallback springen,
          // bei Abbruch direkt beenden.
          if (!_isSensorError(e.toString())) {
            if (mounted) setState(() => _loading = false);
            return;
          }
          // Bei Sensorfehler: weiter zum Fallback unten
        }
      }

      // 4. Fallback: Geräte-PIN / Passcode
      //    Wird nur erreicht wenn Biometrie fehlschlug (Sensorfehler) oder
      //    gar kein biometrisches Merkmal vorhanden ist.
      if (!authenticated) {
        _recordFailedAttempt(account.username);

        if (_isLockedOut(account.username)) {
          _setError(_lockoutMessage(account.username));
          return;
        }

        try {
          authenticated = await _localAuth.authenticate(
            localizedReason: Platform.isAndroid
                ? 'Bitte Geräte-PIN oder Muster eingeben'
                : 'Bitte Passcode eingeben',
            options: AuthenticationOptions(
              biometricOnly: false, // erlaubt PIN/Passcode
              stickyAuth: true,
              useErrorDialogs: _useErrorDialogs, // false=iOS, true=Android
              sensitiveTransaction: true,
            ),
          );
        } catch (e) {
          if (mounted) _setError(_friendlyBiometricError(e.toString()));
          return;
        }
      }

      if (!authenticated) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      // 5. Passwort aus Secure Storage holen
      String? password;
      try {
        password = await _credService.getPassword(account.username);
      } catch (_) {
        password = null;
      }

      if (password == null) {
        _setError(
          'Kein gespeichertes Passwort. Bitte einmal manuell anmelden.',
        );
        return;
      }

      // 6. Server-Login
      bool ok = false;
      try {
        ok = await _service.login(account.username, password);
      } catch (_) {
        ok = false;
      }

      if (!mounted) return;

      if (ok) {
        _clearFailedAttempts(account.username);
        _afterSuccessfulLogin(account.username);
      } else {
        await _credService.removeAccount(account.username);
        await _loadSavedAccounts();
        _setError('Passwort ungültig. Bitte manuell anmelden.');
      }
    } catch (e) {
      if (!mounted) return;
      _setError(
        'Authentifizierung fehlgeschlagen: ${e.toString().split('\n').first}',
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Gibt true zurück wenn der Fehler ein Hardware-/Sensor-Problem ist
  /// (kein Nutzerabbruch) → dann PIN-Fallback sinnvoll.
  bool _isSensorError(String msg) {
    return msg.contains('NotEnrolled') ||
        msg.contains('NotAvailable') ||
        msg.contains('PasscodeNotSet') ||
        msg.contains('PermanentlyLockedOut') ||
        msg.contains('LockedOut') ||
        msg.contains('HardwareUnavailable') || // Android spezifisch
        msg.contains('BiometricUnavailable') || // Android spezifisch
        msg.contains('NoBiometrics'); // Android spezifisch
  }

  String _biometricReason(String username) {
    if (_hasFaceId) {
      final label = Platform.isIOS ? 'Face ID' : 'Gesichtserkennung';
      return '$label: Als $username anmelden';
    }
    if (_hasFingerprint) return 'Fingerabdruck: Als $username anmelden';
    return 'Biometrie: Als $username anmelden';
  }

  String _friendlyBiometricError(String msg) {
    if (msg.contains('NotEnrolled') || msg.contains('NoBiometrics')) {
      return 'Keine Biometrie eingerichtet.';
    }
    if (msg.contains('NotAvailable') ||
        msg.contains('HardwareUnavailable') ||
        msg.contains('BiometricUnavailable')) {
      return 'Biometrie nicht verfügbar.';
    }
    if (msg.contains('LockedOut') || msg.contains('PermanentlyLockedOut')) {
      return 'Biometrie gesperrt. Bitte PIN nutzen.';
    }
    if (msg.contains('PasscodeNotSet')) return 'Kein Geräte-PIN eingerichtet.';
    return 'Authentifizierung fehlgeschlagen.';
  }

  // ──────────────────────────────────────────────────────────────────────────
  // KONTO ENTFERNEN
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _removeAccount(SavedAccount account) async {
    try {
      await _credService.removeAccount(account.username);
      _clearFailedAttempts(account.username);
      await _loadSavedAccounts();
    } catch (_) {}
  }

  Future<void> _loadSavedAccounts() async {
    try {
      final accounts = await _credService.loadAccounts();
      if (mounted) setState(() => _savedAccounts = accounts);
    } catch (_) {
      if (mounted) setState(() => _savedAccounts = []);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // MANUELLER LOGIN
  // ──────────────────────────────────────────────────────────────────────────

  Future<void> _login() async {
    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;

    if (username.isEmpty) {
      _focusUser.requestFocus();
      _setError('Benutzername fehlt.');
      return;
    }
    if (password.isEmpty) {
      _focusPass.requestFocus();
      _setError('Passwort fehlt.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final ok = await _service.login(username, password);
      if (!mounted) return;

      if (ok) {
        if (_saveLogin) {
          await _credService.saveCredentials(
            username: username,
            password: password,
          );
        }
        _afterSuccessfulLogin(username);
      } else {
        _setError('Falscher Benutzername oder Passwort.');
      }
    } catch (e) {
      if (mounted) _setError(e.toString().replaceAll('Exception:', '').trim());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _afterSuccessfulLogin(String username) {
    _service
        .fetchProfileImage()
        .then((img) {
          if (img != null) {
            _credService.updateProfileImage(username, base64Encode(img));
          }
        })
        .catchError((_) {});
    _navigateHome();
  }

  void _setError(String message) {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _error = message;
    });
  }

  void _navigateHome() {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => HomeScreen(service: _service),
        transitionsBuilder: (_, a, _, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  Color _withAlpha(Color color, double alpha) =>
      color.withOpacity(alpha.clamp(0.0, 1.0));

  // ──────────────────────────────────────────────────────────────────────────
  // UI
  // ──────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fade,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: MediaQuery.of(context).size.height * 0.10),
                _buildLogo(),
                const SizedBox(height: 20),
                const Center(
                  child: Text(
                    'POKYH',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    'LBS Brixen · WebUntis',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).size.height * 0.06),

                // Gespeicherte Konten
                if (_savedAccounts.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Gespeicherte Konten',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                  ),
                  for (final account in _savedAccounts)
                    _SavedAccountTile(
                      account: account,
                      biometricIcon: _bestBiometricIcon,
                      biometricLabel: _bestBiometricLabel,
                      hasFaceId: _hasFaceId,
                      hasFingerprint: _hasFingerprint,
                      loading: _loading,
                      failedAttempts: _failedAttempts[account.username] ?? 0,
                      maxAttempts: _kMaxBiometricAttempts,
                      isLockedOut: _isLockedOut(account.username),
                      onTap: () => _biometricLogin(account),
                      onRemove: () => _removeAccount(account),
                      withAlpha: _withAlpha,
                    ),
                  const SizedBox(height: 20),
                  _buildDividerWithText('oder manuell anmelden'),
                  const SizedBox(height: 20),
                ] else
                  SizedBox(height: MediaQuery.of(context).size.height * 0.02),

                // Eingabefelder
                _buildField(
                  controller: _userCtrl,
                  placeholder: 'Username',
                  icon: CupertinoIcons.person_fill,
                  focusNode: _focusUser,
                  textAction: TextInputAction.next,
                  onSubmit: (_) => _focusPass.requestFocus(),
                  autocorrect: false,
                  autocapitalize: TextCapitalization.none,
                ),
                const SizedBox(height: 12),
                _buildField(
                  controller: _passCtrl,
                  placeholder: 'Password',
                  icon: CupertinoIcons.lock_fill,
                  obscure: _obscure,
                  focusNode: _focusPass,
                  textAction: TextInputAction.done,
                  onSubmit: (_) => _login(),
                  autocorrect: false,
                  autocapitalize: TextCapitalization.none,
                  suffix: GestureDetector(
                    onTap: () => setState(() => _obscure = !_obscure),
                    child: Icon(
                      _obscure
                          ? CupertinoIcons.eye_slash_fill
                          : CupertinoIcons.eye_fill,
                      color: AppTheme.textTertiary,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Checkbox
                _SaveLoginCheckbox(
                  value: _saveLogin,
                  hasFaceId: _hasFaceId,
                  hasFingerprint: _hasFingerprint,
                  onChanged: (v) => setState(() => _saveLogin = v),
                  withAlpha: _withAlpha,
                ),

                // Fehleranzeige
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  child: _error != null
                      ? Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: _withAlpha(AppTheme.danger, 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  CupertinoIcons.exclamationmark_circle_fill,
                                  color: AppTheme.danger,
                                  size: 16,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(
                                      color: AppTheme.danger,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                const SizedBox(height: 24),

                // Login-Button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
                    child: _loading
                        ? const CupertinoActivityIndicator(color: Colors.white)
                        : const Text('Anmelden'),
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogo() {
    return Center(
      child: Container(
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppTheme.accent, AppTheme.accentSoft],
          ),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(
          CupertinoIcons.book_fill,
          color: Colors.white,
          size: 32,
        ),
      ),
    );
  }

  Widget _buildDividerWithText(String text) {
    return Row(
      children: [
        Expanded(child: Divider(color: _withAlpha(AppTheme.textTertiary, 0.2))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            text,
            style: TextStyle(color: AppTheme.textTertiary, fontSize: 12),
          ),
        ),
        Expanded(child: Divider(color: _withAlpha(AppTheme.textTertiary, 0.2))),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String placeholder,
    required IconData icon,
    bool obscure = false,
    FocusNode? focusNode,
    TextInputAction? textAction,
    ValueChanged<String>? onSubmit,
    Widget? suffix,
    bool autocorrect = true,
    TextCapitalization autocapitalize = TextCapitalization.sentences,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscure,
        autocorrect: autocorrect,
        textCapitalization: autocapitalize,
        textInputAction: textAction,
        onSubmitted: onSubmit,
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
        decoration: InputDecoration(
          prefixIcon: Icon(icon, color: AppTheme.textTertiary, size: 18),
          suffixIcon: suffix != null
              ? Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: suffix,
                )
              : null,
          suffixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 0,
          ),
          hintText: placeholder,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// SUB-WIDGETS
// ────────────────────────────────────────────────────────────────────────────

class _SaveLoginCheckbox extends StatelessWidget {
  final bool value;
  final bool hasFaceId;
  final bool hasFingerprint;
  final ValueChanged<bool> onChanged;
  final Color Function(Color, double) withAlpha;

  const _SaveLoginCheckbox({
    required this.value,
    required this.hasFaceId,
    required this.hasFingerprint,
    required this.onChanged,
    required this.withAlpha,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: value ? AppTheme.accent : Colors.transparent,
                  border: Border.all(
                    color: value ? AppTheme.accent : AppTheme.textTertiary,
                    width: 1.5,
                  ),
                  borderRadius: BorderRadius.circular(5),
                ),
                child: value
                    ? const Icon(
                        CupertinoIcons.checkmark,
                        color: Colors.white,
                        size: 13,
                      )
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Login speichern & Biometrie aktivieren',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SavedAccountTile extends StatelessWidget {
  final SavedAccount account;
  final IconData biometricIcon;
  final String biometricLabel;
  final bool hasFaceId;
  final bool hasFingerprint;
  final bool loading;
  final int failedAttempts;
  final int maxAttempts;
  final bool isLockedOut;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final Color Function(Color, double) withAlpha;

  const _SavedAccountTile({
    required this.account,
    required this.biometricIcon,
    required this.biometricLabel,
    required this.hasFaceId,
    required this.hasFingerprint,
    required this.loading,
    required this.failedAttempts,
    required this.maxAttempts,
    required this.isLockedOut,
    required this.onTap,
    required this.onRemove,
    required this.withAlpha,
  });

  @override
  Widget build(BuildContext context) {
    Uint8List? imageBytes;
    if (account.profileImageBase64 != null) {
      try {
        imageBytes = base64Decode(account.profileImageBase64!);
      } catch (_) {}
    }

    final bool disabled = loading || isLockedOut;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AnimatedOpacity(
        opacity: isLockedOut ? 0.5 : 1.0,
        duration: const Duration(milliseconds: 200),
        child: Material(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: disabled ? null : onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _Avatar(
                        imageBytes: imageBytes,
                        username: account.username,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              account.username,
                              style: const TextStyle(
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 3),
                            _AuthChainRow(
                              hasFaceId: hasFaceId,
                              hasFingerprint: hasFingerprint,
                              withAlpha: withAlpha,
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isLockedOut ? Icons.lock_outline : biometricIcon,
                            color: isLockedOut
                                ? AppTheme.danger
                                : AppTheme.accent,
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: onRemove,
                            child: Icon(
                              CupertinoIcons.xmark_circle_fill,
                              color: withAlpha(AppTheme.textTertiary, 0.4),
                              size: 26,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  if (failedAttempts > 0 && !isLockedOut) ...[
                    const SizedBox(height: 8),
                    _AttemptsIndicator(
                      failed: failedAttempts,
                      max: maxAttempts,
                      withAlpha: withAlpha,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final Uint8List? imageBytes;
  final String username;

  const _Avatar({required this.imageBytes, required this.username});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: imageBytes == null
            ? const LinearGradient(
                colors: [AppTheme.accent, AppTheme.accentSoft],
              )
            : null,
        image: imageBytes != null
            ? DecorationImage(
                image: MemoryImage(imageBytes!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: imageBytes == null
          ? Center(
              child: Text(
                username.isNotEmpty ? username[0].toUpperCase() : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                ),
              ),
            )
          : null,
    );
  }
}

class _AuthChainRow extends StatelessWidget {
  final bool hasFaceId;
  final bool hasFingerprint;
  final Color Function(Color, double) withAlpha;

  const _AuthChainRow({
    required this.hasFaceId,
    required this.hasFingerprint,
    required this.withAlpha,
  });

  @override
  Widget build(BuildContext context) {
    // Zeigt die verfügbare Biometrie-Kette als kleine Icons an
    final steps = <Widget>[];

    if (hasFaceId) {
      steps.add(
        _Step(
          icon: Icons.face,
          label: Platform.isIOS ? 'Face ID' : 'Gesicht',
          active: true,
          withAlpha: withAlpha,
        ),
      );
    }

    if (hasFaceId && hasFingerprint) {
      steps.add(_Arrow(withAlpha: withAlpha));
    }

    if (hasFingerprint) {
      steps.add(
        _Step(
          icon: Icons.fingerprint,
          label: 'Fingerabdruck',
          active: true,
          withAlpha: withAlpha,
        ),
      );
    }

    if (steps.isNotEmpty) {
      steps.add(_Arrow(withAlpha: withAlpha));
    }

    steps.add(
      _Step(
        icon: Platform.isAndroid ? Icons.pin : Icons.lock_outline,
        label: Platform.isAndroid ? 'PIN' : 'Passcode',
        active: false,
        withAlpha: withAlpha,
      ),
    );

    return Row(mainAxisSize: MainAxisSize.min, children: steps);
  }
}

class _Step extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final Color Function(Color, double) withAlpha;

  const _Step({
    required this.icon,
    required this.label,
    required this.active,
    required this.withAlpha,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 11,
          color: active
              ? AppTheme.accent
              : withAlpha(AppTheme.textTertiary, 0.45),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: active
                ? AppTheme.textSecondary
                : withAlpha(AppTheme.textTertiary, 0.45),
          ),
        ),
      ],
    );
  }
}

class _Arrow extends StatelessWidget {
  final Color Function(Color, double) withAlpha;

  const _Arrow({required this.withAlpha});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Text(
        '→',
        style: TextStyle(
          fontSize: 10,
          color: withAlpha(AppTheme.textTertiary, 0.35),
        ),
      ),
    );
  }
}

class _AttemptsIndicator extends StatelessWidget {
  final int failed;
  final int max;
  final Color Function(Color, double) withAlpha;

  const _AttemptsIndicator({
    required this.failed,
    required this.max,
    required this.withAlpha,
  });

  @override
  Widget build(BuildContext context) {
    final remaining = max - failed;
    return Row(
      children: [
        const Icon(
          CupertinoIcons.exclamationmark_triangle_fill,
          size: 11,
          color: AppTheme.danger,
        ),
        const SizedBox(width: 4),
        Text(
          '$remaining Versuch${remaining == 1 ? '' : 'e'} verbleibend',
          style: const TextStyle(fontSize: 11, color: AppTheme.danger),
        ),
        const SizedBox(width: 6),
        Row(
          children: List.generate(
            max,
            (i) => Container(
              width: 6,
              height: 6,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < failed
                    ? AppTheme.danger
                    : withAlpha(AppTheme.textTertiary, 0.25),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
