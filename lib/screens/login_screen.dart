import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:local_auth/local_auth.dart';

import '../services/webuntis_service.dart';
import '../theme/app_theme.dart';
import '../services/secure_credential_service.dart';
import 'home_screen.dart';

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

  late final AnimationController _anim;
  late final Animation<double> _fade;

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
    await _loadSavedAccounts();
    await _detectBiometrics();
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

  // ── Biometric detection ───────────────────────────────────────────────────

  Future<void> _detectBiometrics() async {
    try {
      final canCheck = await _localAuth.canCheckBiometrics;
      final isSupported = await _localAuth.isDeviceSupported();
      if (canCheck || isSupported) {
        final biometrics = await _localAuth.getAvailableBiometrics();
        if (mounted) setState(() => _availableBiometrics = biometrics);
      }
    } catch (_) {
      // Silently ignore — biometric features simply won't show
    }
  }

  /// Returns the best matching icon for what the device actually supports.
  ///
  /// IMPORTANT: CupertinoIcons does NOT contain any face-id icon (confirmed
  /// missing from the package — see flutter/flutter#167394). All biometric
  /// icons intentionally use verified Material Icons to prevent build errors.
  IconData get _biometricIcon {
    if (_availableBiometrics.contains(BiometricType.face)) {
      return Icons.face_unlock_outlined;    // ✅ verified Material icon
    } else if (_availableBiometrics.contains(BiometricType.fingerprint)) {
      return Icons.fingerprint;             // ✅ verified Material icon
    } else if (_availableBiometrics.contains(BiometricType.iris)) {
      return Icons.remove_red_eye_outlined; // ✅ verified Material icon
    } else if (_availableBiometrics.contains(BiometricType.strong) ||
        _availableBiometrics.contains(BiometricType.weak)) {
      return Icons.lock_outline;            // ✅ verified Material icon
    }
    return Icons.smartphone_outlined;      // ✅ verified Material icon fallback
  }

  String get _biometricLabel {
    if (_availableBiometrics.contains(BiometricType.face)) return 'Face ID';
    if (_availableBiometrics.contains(BiometricType.fingerprint)) {
      return 'Fingerabdruck';
    }
    if (_availableBiometrics.contains(BiometricType.iris)) return 'Iris-Scan';
    return 'Geräte-PIN';
  }

  // ── Saved accounts ────────────────────────────────────────────────────────

  Future<void> _loadSavedAccounts() async {
    final accounts = await _credService.loadAccounts();
    if (mounted) setState(() => _savedAccounts = accounts);
  }

  /// Triggers the native OS authentication prompt.
  ///
  /// iOS:     Face ID → Touch ID → Device Passcode
  /// Android: Fingerprint → Face → Iris → PIN → Pattern → Password
  ///
  /// [biometricOnly: false] ensures the OS always shows a fallback to
  /// device PIN/password when biometrics fail or aren't enrolled.
  Future<void> _biometricLogin(SavedAccount account) async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      if (!isDeviceSupported) {
        _setError('Dieses Gerät unterstützt keine Gerätesicherheit.');
        return;
      }

      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Als ${account.username} anmelden',
        options: const AuthenticationOptions(
          biometricOnly: false,       // allows PIN/password fallback
          stickyAuth: true,           // keeps prompt alive when app backgrounds
          useErrorDialogs: true,      // OS shows its own error dialogs
          sensitiveTransaction: false,
        ),
      );

      if (!authenticated) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final password = await _credService.getPassword(account.username);
      if (password == null) {
        _setError(
          'Kein gespeichertes Passwort. Bitte einmal manuell anmelden.',
        );
        return;
      }

      final ok = await _service.login(account.username, password);
      if (!mounted) return;

      if (ok) {
        _afterSuccessfulLogin(account.username);
      } else {
        _setError('Anmeldung fehlgeschlagen — Passwort geändert?');
      }
    } on Exception catch (e) {
      if (!mounted) return;
      _setError(_friendlyBiometricError(e.toString()));
    }
  }

  /// Maps raw exception messages to user-friendly German strings.
  String _friendlyBiometricError(String msg) {
    if (msg.contains('NotEnrolled')) {
      return 'Keine Biometrie eingerichtet. Bitte manuell anmelden.';
    } else if (msg.contains('NotAvailable')) {
      return 'Biometrie nicht verfügbar. Bitte manuell anmelden.';
    } else if (msg.contains('PermanentlyLockedOut') ||
        msg.contains('LockedOut')) {
      return 'Biometrie gesperrt. Bitte Geräte-PIN nutzen oder manuell anmelden.';
    } else if (msg.contains('PasscodeNotSet')) {
      return 'Kein Geräte-PIN eingerichtet. Bitte in den Einstellungen aktivieren.';
    }
    return 'Authentifizierung fehlgeschlagen.';
  }

  Future<void> _removeAccount(SavedAccount account) async {
    await _credService.removeAccount(account.username);
    await _loadSavedAccounts();
  }

  // ── Normal login ──────────────────────────────────────────────────────────

  Future<void> _login() async {
    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;

    if (username.isEmpty) {
      _focusUser.requestFocus();
      _setError('Bitte Benutzername eingeben.');
      return;
    }
    if (password.isEmpty) {
      _focusPass.requestFocus();
      _setError('Bitte Passwort eingeben.');
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
        _setError('Benutzername oder Passwort falsch.');
      }
    } on WebUntisException catch (e) {
      if (mounted) _setError(e.message);
    } catch (e) {
      if (mounted) _setError('$e');
    }
  }

  /// Shared post-login logic: fetch profile image & navigate.
  void _afterSuccessfulLogin(String username) {
    _service.fetchProfileImage().then((img) {
      if (img != null) {
        _credService.updateProfileImage(username, base64Encode(img));
      }
    });
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
        pageBuilder: (_, __, ___) => HomeScreen(service: _service),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

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

                // ── Logo ──────────────────────────────────────────────────
                Center(
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
                ),
                const SizedBox(height: 20),
                const Center(
                  child: Text(
                    'POCKYH',
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

                // ── Saved account tiles ───────────────────────────────────
                if (_savedAccounts.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Gespeicherte Konten',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textTertiary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  for (final account in _savedAccounts)
                    _SavedAccountTile(
                      account: account,
                      biometricIcon: _biometricIcon,
                      biometricLabel: _biometricLabel,
                      loading: _loading,
                      onTap: () => _biometricLogin(account),
                      onRemove: () => _removeAccount(account),
                    ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Divider(
                          color: AppTheme.textTertiary.withValues(alpha: 0.2),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Text(
                          'oder',
                          style: TextStyle(
                            color: AppTheme.textTertiary,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Divider(
                          color: AppTheme.textTertiary.withValues(alpha: 0.2),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                ] else
                  SizedBox(height: MediaQuery.of(context).size.height * 0.02),

                // ── Input fields ──────────────────────────────────────────
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
                  enableSuggestions: false,
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

                // ── Save login checkbox ───────────────────────────────────
                _SaveLoginCheckbox(
                  value: _saveLogin,
                  biometricLabel: _biometricLabel,
                  onChanged: (v) => setState(() => _saveLogin = v),
                ),

                // ── Error banner (animated) ───────────────────────────────
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
                        color: AppTheme.danger.withValues(alpha: 0.1),
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

                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _login,
                    child: _loading
                        ? const CupertinoActivityIndicator(
                      color: Colors.white,
                    )
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
    bool enableSuggestions = true,
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
        enableSuggestions: enableSuggestions,
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

// ── Sub-widgets ────────────────────────────────────────────────────────────

class _SaveLoginCheckbox extends StatelessWidget {
  final bool value;
  final String biometricLabel;
  final ValueChanged<bool> onChanged;

  const _SaveLoginCheckbox({
    required this.value,
    required this.biometricLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Row(
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
              'Login speichern – $biometricLabel aktivieren',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
              ),
            ),
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
  final bool loading;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  const _SavedAccountTile({
    required this.account,
    required this.biometricIcon,
    required this.biometricLabel,
    required this.loading,
    required this.onTap,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    Uint8List? imageBytes;
    if (account.profileImageBase64 != null) {
      try {
        imageBytes = base64Decode(account.profileImageBase64!);
      } catch (_) {
        // Corrupted base64 — fall back to initials avatar silently
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 12,
            ),
            child: Row(
              children: [
                // Avatar
                Container(
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
                      image: MemoryImage(imageBytes),
                      fit: BoxFit.cover,
                    )
                        : null,
                  ),
                  child: imageBytes == null
                      ? Center(
                    child: Text(
                      account.username.isNotEmpty
                          ? account.username[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  )
                      : null,
                ),
                const SizedBox(width: 14),

                // Username + subtitle
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
                      const SizedBox(height: 2),
                      Text(
                        'Mit $biometricLabel anmelden',
                        style: TextStyle(
                          color: AppTheme.textTertiary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                // Dynamic biometric icon + remove button
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(biometricIcon, color: AppTheme.accent, size: 24),
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: onRemove,
                      child: Icon(
                        CupertinoIcons.xmark_circle_fill,
                        color: AppTheme.textTertiary.withValues(alpha: 0.4),
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}