import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/reminder_service.dart';
import '../services/webuntis_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_message.dart';
import '../widgets/top_bar_actions.dart';

bool get _isIOS => Platform.isIOS;

class RemindersScreen extends StatefulWidget {
  final WebUntisService service;
  const RemindersScreen({super.key, required this.service});

  @override
  State<RemindersScreen> createState() => _RemindersScreenState();
}

class _RemindersScreenState extends State<RemindersScreen> {
  final _service = ReminderService();
  List<ClassRoom> _classes = [];
  String? _selectedClassId;
  StreamSubscription<List<ClassRoom>>? _classesSub;
  bool _isAdmin = false;
  bool _adminLoaded = false;

  // Auto-Join (static verhindert doppelten Aufruf über Hot-Restart hinweg)
  static bool _autoJoinDone = false;
  bool _autoJoinLoading = false;
  String? _autoJoinError;

  bool _streamHasEmitted = false;
  Timer? _loadingTimeout;
  String? _myStableUid;
  String? _myUsername;

  @override
  void initState() {
    super.initState();
    _loadAdmin();
    _loadMyStableUid();
    // Auto-Join sofort beim Öffnen starten (nicht auf Stream warten)
    _maybeAutoJoin();
    // Timeout: Falls Firestore nach 8 Sek. keine Daten liefert (kein Internet)
    _loadingTimeout = Timer(const Duration(seconds: 8), () {
      if (mounted && !_streamHasEmitted) {
        setState(() {
          _streamHasEmitted = true;
          if (_classes.isEmpty && _autoJoinError == null && !_autoJoinLoading) {
            _autoJoinError =
                'Verbindung fehlgeschlagen.\nBitte Internetverbindung prüfen und erneut versuchen.';
          }
        });
      }
    });
    _classesSub = _service.classesStream().listen((classes) {
      if (!mounted) return;
      setState(() {
        _streamHasEmitted = true;
        _loadingTimeout?.cancel();
        _classes = classes;
        if (_selectedClassId == null && classes.isNotEmpty) {
          _selectedClassId = classes.first.id;
          _autoJoinError = null;
        }
        if (_selectedClassId != null &&
            !classes.any((c) => c.id == _selectedClassId)) {
          _selectedClassId = classes.isNotEmpty ? classes.first.id : null;
        }
      });
      if (_selectedClassId != null) {
        _service.cleanupExpired(_selectedClassId!);
      }
    });
  }

  void _maybeAutoJoin() {
    final klasseId = widget.service.klasseId;
    final klasseName = widget.service.klasseName;
    if (klasseId == null || klasseName == null || klasseName.isEmpty) return;
    if (_autoJoinDone) return;
    _autoJoinDone = true;
    _tryAutoJoin();
  }

  Future<void> _tryAutoJoin() async {
    final klasseId = widget.service.klasseId;
    final klasseName = widget.service.klasseName;
    if (klasseId == null || klasseName == null || klasseName.isEmpty) return;

    debugPrint('[RemindersScreen] Auto-Join: "$klasseName" (id=$klasseId)');
    if (mounted)
      setState(() {
        _autoJoinLoading = true;
        _autoJoinError = null;
      });

    try {
      await _service.autoJoinOrCreateWebuntisClass(klasseName, klasseId);
      if (mounted) setState(() => _autoJoinLoading = false);
    } catch (e) {
      debugPrint('[RemindersScreen] Auto-Join Fehler: $e');
      _autoJoinDone = false; // Retry erlauben
      if (mounted) {
        setState(() {
          _autoJoinLoading = false;
          _autoJoinError =
              'Automatische Zuweisung fehlgeschlagen.\nTritt manuell bei.';
        });
      }
    }
  }

  Future<void> _loadMyStableUid() async {
    final uid = await AuthService.instance.resolveStableUid();
    if (mounted) {
      setState(() {
        _myStableUid = uid;
        _myUsername = AuthService.instance.username;
      });
    }
  }

  Future<void> _loadAdmin() async {
    final admin = await _service.isAdmin();
    if (mounted)
      setState(() {
        _isAdmin = admin;
        _adminLoaded = true;
      });
  }

  @override
  void dispose() {
    _classesSub?.cancel();
    _loadingTimeout?.cancel();
    super.dispose();
  }

  // ── Class actions ──────────────────────────────────────────────────────────

  void _showJoinOrCreateSheet() {
    if (_isIOS) {
      showCupertinoModalPopup(
        context: context,
        builder: (ctx) => CupertinoActionSheet(
          title: const Text('Klasse'),
          actions: [
            if (_isAdmin)
              CupertinoActionSheetAction(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showCreateClassDialog();
                },
                child: const Text('Neue Klasse erstellen'),
              ),
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _showJoinClassDialog();
              },
              child: const Text('Klasse beitreten'),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: context.appSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Klasse',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
              if (_isAdmin)
                ListTile(
                  leading: Icon(
                    Icons.add_circle_outline,
                    color: AppTheme.accent,
                  ),
                  title: Text(
                    'Neue Klasse erstellen',
                    style: TextStyle(color: context.appTextPrimary),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showCreateClassDialog();
                  },
                ),
              ListTile(
                leading: Icon(Icons.group_add_outlined, color: AppTheme.accent),
                title: Text(
                  'Klasse beitreten',
                  style: TextStyle(color: context.appTextPrimary),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  _showJoinClassDialog();
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    }
  }

  void _showCreateClassDialog() {
    final controller = TextEditingController();
    _showInputDialog(
      title: 'Klasse erstellen',
      placeholder: 'Klassenname',
      controller: controller,
      confirmLabel: 'Erstellen',
      onConfirm: () async {
        final name = controller.text.trim();
        if (name.isEmpty) return;
        final cls = await _service.createClass(name);
        if (!mounted) return;
        setState(() => _selectedClassId = cls.id);
        _showCodeSheet(cls);
      },
    );
  }

  void _showJoinClassDialog() {
    final controller = TextEditingController();
    _showInputDialog(
      title: 'Klasse beitreten',
      placeholder: 'Klassen-Code (6 Zeichen)',
      controller: controller,
      confirmLabel: 'Beitreten',
      onConfirm: () async {
        final code = controller.text.trim();
        if (code.isEmpty) return;
        final cls = await _service.joinClass(code, isAdminUser: _isAdmin);
        if (!mounted) return;
        setState(() => _selectedClassId = cls.id);
      },
    );
  }

  void _showCodeSheet(ClassRoom cls) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.appSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isIOS
                    ? CupertinoIcons.checkmark_seal_fill
                    : Icons.check_circle,
                color: AppTheme.success,
                size: 40,
              ),
              const SizedBox(height: 12),
              Text(
                'Klasse erstellt!',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: context.appTextPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Teile diesen Code mit deiner Klasse:',
                style: TextStyle(fontSize: 14, color: context.appTextSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: cls.code));
                  Navigator.pop(ctx);
                  _showToast('Code kopiert: ${cls.code}');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 16,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    cls.code,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.accent,
                      letterSpacing: 6,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Tippen zum Kopieren',
                style: TextStyle(fontSize: 12, color: context.appTextTertiary),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _showMembersSheet(ClassRoom cls) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.appSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _MembersSheet(cls: cls),
    );
  }

  void _showLeaveClassDialog(ClassRoom cls) {
    if (_isIOS) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Klasse verlassen'),
          content: Text('Möchtest du „${cls.name}" wirklich verlassen?'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () async {
                Navigator.pop(ctx);
                await _service.leaveClass(cls.id);
              },
              child: const Text('Verlassen'),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.appSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Klasse verlassen',
            style: TextStyle(color: context.appTextPrimary),
          ),
          content: Text(
            'Möchtest du „${cls.name}" wirklich verlassen?',
            style: TextStyle(color: context.appTextSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _service.leaveClass(cls.id);
              },
              child: Text(
                'Verlassen',
                style: TextStyle(color: AppTheme.danger),
              ),
            ),
          ],
        ),
      );
    }
  }

  // ── Reminder actions ───────────────────────────────────────────────────────

  void _showCreateReminderSheet() {
    final classId = _selectedClassId;
    if (classId == null) return;
    if (_isIOS) {
      showCupertinoModalPopup(
        context: context,
        builder: (ctx) => _IosCreateReminderSheet(
          classId: classId,
          service: _service,
          onCreated: () => Navigator.pop(ctx),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: context.appSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (ctx) => _AndroidCreateReminderSheet(
          classId: classId,
          service: _service,
          onCreated: () => Navigator.pop(ctx),
        ),
      );
    }
  }

  void _confirmDeleteReminder(Reminder reminder) {
    if (_isIOS) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Erinnerung löschen'),
          content: Text('„${reminder.title}" wirklich löschen?'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () async {
                Navigator.pop(ctx);
                await _service.deleteReminder(reminder.classId, reminder.id);
                if (mounted) _showToast('Erinnerung gelöscht');
              },
              child: const Text('Löschen'),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.appSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Erinnerung löschen',
            style: TextStyle(color: context.appTextPrimary),
          ),
          content: Text(
            '„${reminder.title}" wirklich löschen?',
            style: TextStyle(color: context.appTextSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(ctx);
                await _service.deleteReminder(reminder.classId, reminder.id);
                if (mounted) _showToast('Erinnerung gelöscht');
              },
              child: Text('Löschen', style: TextStyle(color: AppTheme.danger)),
            ),
          ],
        ),
      );
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  void _showInputDialog({
    required String title,
    required String placeholder,
    required TextEditingController controller,
    required String confirmLabel,
    required Future<void> Function() onConfirm,
  }) {
    bool loading = false;
    String? errorText;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setInner) => AlertDialog(
          backgroundColor: context.appSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(title, style: TextStyle(color: context.appTextPrimary)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: controller,
                autofocus: true,
                style: TextStyle(color: context.appTextPrimary),
                decoration: InputDecoration(
                  hintText: placeholder,
                  hintStyle: TextStyle(color: context.appTextTertiary),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: context.appBorder.withValues(alpha: 0.4),
                    ),
                  ),
                  focusedBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: AppTheme.accent),
                  ),
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 8),
                Text(
                  errorText!,
                  style: TextStyle(fontSize: 12, color: AppTheme.danger),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: loading
                  ? null
                  : () async {
                      setInner(() {
                        loading = true;
                        errorText = null;
                      });
                      try {
                        await onConfirm();
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        if (ctx.mounted) {
                          setInner(() {
                            loading = false;
                            errorText = simplifyErrorMessage(e);
                          });
                        }
                      }
                    },
              child: loading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppTheme.accent,
                      ),
                    )
                  : Text(
                      confirmLabel,
                      style: TextStyle(color: AppTheme.accent),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showToast(String message) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (ctx) => _ToastOverlay(message: message),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2), () => entry.remove());
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final selectedClass = _classes
        .where((c) => c.id == _selectedClassId)
        .firstOrNull;

    return Scaffold(
      backgroundColor: context.appBg,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(
                children: [
                  if (Navigator.canPop(context))
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: context.appSurface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _isIOS
                              ? CupertinoIcons.chevron_left
                              : Icons.arrow_back,
                          size: 16,
                          color: context.appTextSecondary,
                        ),
                      ),
                    ),
                  if (Navigator.canPop(context)) const SizedBox(width: 12),
                  Text(
                    'Erinnerungen',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: context.appTextPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  TopBarActions(service: widget.service),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Class selector row
            SizedBox(
              height: 38,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  ..._classes.map(
                    (cls) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: GestureDetector(
                        onLongPress: () => _showLeaveClassDialog(cls),
                        child: _ClassChip(
                          label: cls.name,
                          code: cls.code,
                          selected: _selectedClassId == cls.id,
                          memberCount: cls.members.length,
                          onTap: () {
                            if (_selectedClassId == cls.id) {
                              _showMembersSheet(cls);
                            } else {
                              setState(() => _selectedClassId = cls.id);
                              _service.cleanupExpired(cls.id);
                            }
                          },
                          onMembersTap: () => _showMembersSheet(cls),
                        ),
                      ),
                    ),
                  ),
                  // Show join/create button only if admin OR not yet in a class
                  if (_adminLoaded && (_isAdmin || _classes.isEmpty))
                    GestureDetector(
                      onTap: _showJoinOrCreateSheet,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: context.appSurface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: context.appBorder.withValues(alpha: 0.4),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isIOS ? CupertinoIcons.plus : Icons.add,
                              size: 14,
                              color: context.appTextSecondary,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _isAdmin ? 'Klasse' : 'Beitreten',
                              style: TextStyle(
                                fontSize: 13,
                                color: context.appTextSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 14),

            // Content
            Expanded(
              child: !_streamHasEmitted
                  ? _EmptyClassesState(
                      isAdmin: _isAdmin,
                      onJoinOrCreate: _showJoinOrCreateSheet,
                      isLoading: true,
                      errorMessage: null,
                      onRetry: _tryAutoJoin,
                    )
                  : _classes.isEmpty
                  ? _EmptyClassesState(
                      isAdmin: _isAdmin,
                      onJoinOrCreate: _showJoinOrCreateSheet,
                      isLoading: _autoJoinLoading,
                      errorMessage: _autoJoinError,
                      onRetry: _tryAutoJoin,
                    )
                  : selectedClass == null
                  ? const SizedBox.shrink()
                  : _RemindersList(
                      classRoom: selectedClass,
                      service: _service,
                      onDelete: _confirmDeleteReminder,
                      currentUserStableUid: _myStableUid,
                      currentUsername: _myUsername,
                      isAdmin: _isAdmin,
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: _selectedClassId != null && _classes.isNotEmpty
          ? FloatingActionButton(
              onPressed: _showCreateReminderSheet,
              backgroundColor: AppTheme.accent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }
}

// ── Class chip ────────────────────────────────────────────────────────────────

class _ClassChip extends StatelessWidget {
  final String label;
  final String code;
  final bool selected;
  final int memberCount;
  final VoidCallback onTap;
  final VoidCallback onMembersTap;

  const _ClassChip({
    required this.label,
    required this.code,
    required this.selected,
    required this.memberCount,
    required this.onTap,
    required this.onMembersTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.only(
          left: 14,
          right: selected ? 8 : 14,
          top: 8,
          bottom: 8,
        ),
        decoration: BoxDecoration(
          color: selected ? AppTheme.accent : context.appSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppTheme.accent
                : context.appBorder.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : context.appTextSecondary,
              ),
            ),
            if (selected) ...[
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onMembersTap,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _isIOS ? CupertinoIcons.person_2_fill : Icons.group,
                    size: 12,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyClassesState extends StatelessWidget {
  final VoidCallback onJoinOrCreate;
  final VoidCallback onRetry;
  final bool isAdmin;
  final bool isLoading;
  final String? errorMessage;

  const _EmptyClassesState({
    required this.onJoinOrCreate,
    required this.onRetry,
    required this.isAdmin,
    required this.isLoading,
    this.errorMessage,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: isLoading
                  ? Padding(
                      padding: const EdgeInsets.all(18),
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: AppTheme.accent,
                      ),
                    )
                  : Icon(
                      _isIOS
                          ? CupertinoIcons.bell_fill
                          : Icons.notifications_outlined,
                      size: 28,
                      color: AppTheme.accent,
                    ),
            ),
            const SizedBox(height: 18),
            Text(
              isLoading ? 'Klasse wird erkannt...' : 'Noch keine Klasse',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.appTextPrimary,
              ),
            ),
            const SizedBox(height: 8),
            if (isLoading)
              Text(
                'Deine WebUntis-Klasse wird automatisch erkannt.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: context.appTextSecondary,
                  height: 1.5,
                ),
              )
            else if (errorMessage != null) ...[
              Text(
                errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.danger,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: onRetry,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: context.appSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: context.appBorder.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Text(
                    'Erneut versuchen',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppTheme.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ] else
              Text(
                'Deine WebUntis-Klasse wird automatisch erkannt. Falls das nicht klappt, tritt manuell bei.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: context.appTextSecondary,
                  height: 1.5,
                ),
              ),
            if (!isLoading) ...[
              const SizedBox(height: 24),
              GestureDetector(
                onTap: onJoinOrCreate,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    isAdmin
                        ? 'Klasse beitreten oder erstellen'
                        : 'Manuell beitreten',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Reminders list ────────────────────────────────────────────────────────────

class _RemindersList extends StatelessWidget {
  final ClassRoom classRoom;
  final ReminderService service;
  final void Function(Reminder) onDelete;
  final String? currentUserStableUid;
  final String? currentUsername;
  final bool isAdmin;

  const _RemindersList({
    required this.classRoom,
    required this.service,
    required this.onDelete,
    required this.isAdmin,
    this.currentUserStableUid,
    this.currentUsername,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Reminder>>(
      stream: service.remindersStream(classRoom.id),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CupertinoActivityIndicator(radius: 14));
        }

        final reminders = snap.data ?? [];
        final active = reminders.where((r) => !r.isExpired).toList();

        if (active.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _isIOS
                      ? CupertinoIcons.checkmark_circle
                      : Icons.check_circle_outline,
                  size: 40,
                  color: context.appTextTertiary,
                ),
                const SizedBox(height: 12),
                Text(
                  'Keine Erinnerungen',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.appTextSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Tippe auf + um eine Erinnerung\nfür diese Klasse zu erstellen.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    color: context.appTextTertiary,
                    height: 1.5,
                  ),
                ),
                // Info about class code
                const SizedBox(height: 24),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: classRoom.code));
                    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                      SnackBar(
                        content: Text('Code kopiert: ${classRoom.code}'),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        backgroundColor: context.appSurface,
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: context.appSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: context.appBorder.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isIOS ? CupertinoIcons.share : Icons.share_outlined,
                          size: 14,
                          color: context.appTextTertiary,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          'Code: ${classRoom.code}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: context.appTextSecondary,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
          itemCount: active.length + 1,
          separatorBuilder: (context, index) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      _isIOS ? CupertinoIcons.share : Icons.share_outlined,
                      size: 12,
                      color: context.appTextTertiary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      'Klassen-Code: ${classRoom.code}',
                      style: TextStyle(
                        fontSize: 12,
                        color: context.appTextTertiary,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => Clipboard.setData(
                        ClipboardData(text: classRoom.code),
                      ),
                      child: Icon(
                        _isIOS
                            ? CupertinoIcons.doc_on_clipboard
                            : Icons.content_copy,
                        size: 11,
                        color: context.appTextTertiary,
                      ),
                    ),
                  ],
                ),
              );
            }

            final reminder = active[i - 1];
            return _ReminderCard(
              reminder: reminder,
              onDelete: () => onDelete(reminder),
              currentUserStableUid: currentUserStableUid,
              currentUsername: currentUsername,
              isAdmin: isAdmin,
            );
          },
        );
      },
    );
  }
}

// ── Reminder card ─────────────────────────────────────────────────────────────

class _ReminderCard extends StatefulWidget {
  final Reminder reminder;
  final VoidCallback onDelete;
  final String? currentUserStableUid;
  final String? currentUsername;
  final bool isAdmin;

  const _ReminderCard({
    required this.reminder,
    required this.onDelete,
    required this.isAdmin,
    this.currentUserStableUid,
    this.currentUsername,
  });

  void _openDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ReminderDetailSheet(
        reminder: reminder,
        myStableUid: currentUserStableUid,
        isAdmin: isAdmin,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<_ReminderCard> createState() => _ReminderCardState();
}

class _ReminderCardState extends State<_ReminderCard> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _startTicker();
  }

  void _startTicker() {
    _ticker?.cancel();
    if (widget.reminder.isDue) return;
    // Use 1-second interval so display never shows "0 Min."
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  bool _isCreator() {
    final r = widget.reminder;
    final stable = widget.currentUserStableUid;
    final username = widget.currentUsername;

    // stableUid match (same across all devices for same WebUntis account)
    if (stable != null && stable.isNotEmpty && r.createdByUid.isNotEmpty) {
      if (r.createdByUid == stable) return true;
    }
    // username match – fallback for reminders created before stableUid was stored,
    // or when stableUid was null at creation time and Firebase UID was used instead
    if (username != null && username.isNotEmpty) {
      if (r.createdByUsername == username) return true;
      // Legacy: some reminders stored username directly as createdBy
      if (r.createdByUid == username) return true;
      // createdByName was set to username at creation time
      if (r.createdByName == username) return true;
    }
    return false;
  }

  String _formatRemindAt(DateTime dt) {
    final now = DateTime.now();
    final diff = dt.difference(now);

    if (widget.reminder.isDue) {
      final ago = now.difference(dt);
      if (ago.inMinutes < 60) return 'vor ${ago.inMinutes} Min.';
      if (ago.inHours < 24) return 'vor ${ago.inHours} Std.';
      return 'vor ${ago.inDays} Tag(en)';
    }

    if (diff.inSeconds < 60) return 'gleich';
    if (diff.inMinutes < 60) return 'in ${diff.inMinutes} Min.';
    if (diff.inHours < 24) return 'in ${diff.inHours} Std.';
    if (diff.inDays == 1) return 'morgen';

    final weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '${weekdays[dt.weekday - 1]}, ${pad2(dt.day)}.${pad2(dt.month)} · ${pad2(dt.hour)}:${pad2(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reminder;
    final isDue = r.isDue;

    final statusColor = isDue ? AppTheme.warning : AppTheme.accent;
    final statusLabel = isDue ? 'Fällig' : 'Ausstehend';
    final statusIcon = isDue
        ? (_isIOS ? CupertinoIcons.bell_fill : Icons.notifications_active)
        : (_isIOS ? CupertinoIcons.clock : Icons.access_time_rounded);

    return GestureDetector(
      onTap: () => widget._openDetail(context),
      child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDue
              ? AppTheme.warning.withValues(alpha: 0.3)
              : context.appBorder.withValues(alpha: 0.2),
        ),
        boxShadow: isDue
            ? [
                BoxShadow(
                  color: AppTheme.warning.withValues(alpha: 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  r.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 10, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isCreator() || widget.isAdmin) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: widget.onDelete,
                  child: Icon(
                    _isIOS ? CupertinoIcons.trash : Icons.delete_outline,
                    size: 17,
                    color: context.appTextTertiary,
                  ),
                ),
              ],
            ],
          ),

          // Body
          if (r.body.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              r.body,
              style: TextStyle(
                fontSize: 14,
                color: context.appTextSecondary,
                height: 1.4,
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Footer: creator + time
          Row(
            children: [
              Icon(
                _isIOS ? CupertinoIcons.person_fill : Icons.person_outline,
                size: 12,
                color: context.appTextTertiary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  r.createdByName,
                  style: TextStyle(fontSize: 12, color: context.appTextTertiary),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                _isIOS ? CupertinoIcons.bell : Icons.notifications_outlined,
                size: 12,
                color: statusColor.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 4),
              Text(
                _formatRemindAt(r.remindAt),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: statusColor,
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}

// ── iOS create reminder sheet ─────────────────────────────────────────────────

class _IosCreateReminderSheet extends StatefulWidget {
  final String classId;
  final ReminderService service;
  final VoidCallback onCreated;

  const _IosCreateReminderSheet({
    required this.classId,
    required this.service,
    required this.onCreated,
  });

  @override
  State<_IosCreateReminderSheet> createState() =>
      _IosCreateReminderSheetState();
}

class _IosCreateReminderSheetState extends State<_IosCreateReminderSheet> {
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  DateTime _remindAt = DateTime.now().add(const Duration(hours: 1));
  bool _loading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _loading = true);
    try {
      await widget.service.createReminder(
        classId: widget.classId,
        title: title,
        body: _bodyCtrl.text.trim(),
        remindAt: _remindAt,
      );
      widget.onCreated();
    } catch (e) {
      if (mounted) {
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Fehler'),
            content: Text(simplifyErrorMessage(e)),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        setState(() => _loading = false);
      }
    }
  }

  void _pickDateTime() async {
    DateTime picked = _remindAt;
    await showCupertinoModalPopup(
      context: context,
      builder: (ctx) => Container(
        height: 320,
        color: context.appSurface,
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  child: const Text('Abbrechen'),
                  onPressed: () => Navigator.pop(ctx),
                ),
                CupertinoButton(
                  child: const Text('Fertig'),
                  onPressed: () {
                    setState(() => _remindAt = picked);
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.dateAndTime,
                initialDateTime: _remindAt,
                minimumDate: DateTime.now().add(const Duration(minutes: 1)),
                use24hFormat: true,
                onDateTimeChanged: (dt) => picked = dt,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatExact(DateTime dt) {
    final weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '${weekdays[dt.weekday - 1]}, ${pad2(dt.day)}.${pad2(dt.month)}.${dt.year} · ${pad2(dt.hour)}:${pad2(dt.minute)}';
  }

  String? _formatRelative(DateTime dt) {
    final diff = dt.difference(DateTime.now());
    if (diff.inSeconds < 60) return 'gleich';
    if (diff.inMinutes < 60) return 'in ${diff.inMinutes} Min.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Material(
      type: MaterialType.transparency,
      child: Container(
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.appBorder.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Neue Erinnerung',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: context.appTextPrimary,
                ),
              ),
              const SizedBox(height: 20),
              _CupertinoField(
                controller: _titleCtrl,
                label: 'Titel',
                placeholder: 'z.B. Mathe Hausaufgabe',
                maxLines: 1,
                onChanged: () => setState(() {}),
              ),
              const SizedBox(height: 12),
              _CupertinoField(
                controller: _bodyCtrl,
                label: 'Notiz (optional)',
                placeholder: 'z.B. Seite 42, Aufgabe 3',
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _pickDateTime,
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: context.appCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: context.appBorder.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        CupertinoIcons.calendar_badge_plus,
                        size: 18,
                        color: AppTheme.accent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Erinnerung am',
                              style: TextStyle(
                                fontSize: 11,
                                color: context.appTextTertiary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _formatExact(_remindAt),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: context.appTextPrimary,
                              ),
                            ),
                            if (_formatRelative(_remindAt) != null) ...[
                              const SizedBox(height: 1),
                              Text(
                                _formatRelative(_remindAt)!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.accent,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(
                        CupertinoIcons.chevron_right,
                        size: 16,
                        color: context.appTextTertiary,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: _loading ? null : _submit,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: _titleCtrl.text.isEmpty
                        ? AppTheme.accent.withValues(alpha: 0.5)
                        : AppTheme.accent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Center(
                    child: _loading
                        ? const CupertinoActivityIndicator(
                            color: Colors.white,
                            radius: 10,
                          )
                        : const Text(
                            'Erinnerung erstellen',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

// ── Android create reminder sheet ─────────────────────────────────────────────

class _AndroidCreateReminderSheet extends StatefulWidget {
  final String classId;
  final ReminderService service;
  final VoidCallback onCreated;

  const _AndroidCreateReminderSheet({
    required this.classId,
    required this.service,
    required this.onCreated,
  });

  @override
  State<_AndroidCreateReminderSheet> createState() =>
      _AndroidCreateReminderSheetState();
}

class _AndroidCreateReminderSheetState
    extends State<_AndroidCreateReminderSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();
  DateTime _remindAt = DateTime.now().add(const Duration(hours: 1));
  bool _loading = false;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    try {
      await widget.service.createReminder(
        classId: widget.classId,
        title: _titleCtrl.text.trim(),
        body: _bodyCtrl.text.trim(),
        remindAt: _remindAt,
      );
      widget.onCreated();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(simplifyErrorMessage(e)),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          ),
        );
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _remindAt,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppTheme.accent,
            brightness: Theme.of(context).brightness,
          ),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_remindAt),
      builder: (ctx, child) => Theme(
        data: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppTheme.accent,
            brightness: Theme.of(context).brightness,
          ),
        ),
        child: child!,
      ),
    );
    if (time == null || !mounted) return;

    setState(() {
      _remindAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  String _formatExact(DateTime dt) {
    final weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '${weekdays[dt.weekday - 1]}, ${pad2(dt.day)}.${pad2(dt.month)}.${dt.year}  ${pad2(dt.hour)}:${pad2(dt.minute)}';
  }

  String? _formatRelative(DateTime dt) {
    final diff = dt.difference(DateTime.now());
    if (diff.inSeconds < 60) return 'gleich';
    if (diff.inMinutes < 60) return 'in ${diff.inMinutes} Min.';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final rel = _formatRelative(_remindAt);

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // M3 drag handle
                Center(
                  child: Container(
                    width: 32,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.appBorder.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Row(
                  children: [
                    const Icon(Icons.notifications_outlined, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'Neue Erinnerung',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: context.appTextPrimary,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Title field
                TextFormField(
                  controller: _titleCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(color: context.appTextPrimary),
                  decoration: InputDecoration(
                    labelText: 'Titel',
                    hintText: 'z.B. Mathe Hausaufgabe',
                    hintStyle: TextStyle(color: context.appTextTertiary),
                    prefixIcon: const Icon(Icons.title_outlined),
                    filled: true,
                    fillColor: context.appCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: context.appBorder.withValues(alpha: 0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppTheme.accent, width: 2),
                    ),
                    errorBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppTheme.danger),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Pflichtfeld' : null,
                ),
                const SizedBox(height: 12),

                // Notes field
                TextFormField(
                  controller: _bodyCtrl,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  style: TextStyle(color: context.appTextPrimary),
                  decoration: InputDecoration(
                    labelText: 'Notiz (optional)',
                    hintText: 'z.B. Seite 42, Aufgabe 3',
                    hintStyle: TextStyle(color: context.appTextTertiary),
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(bottom: 48),
                      child: Icon(Icons.notes_outlined),
                    ),
                    filled: true,
                    fillColor: context.appCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: context.appBorder.withValues(alpha: 0.3),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppTheme.accent, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Date/time row (Material InkWell)
                Material(
                  color: context.appCard,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _pickDateTime,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: context.appBorder.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.event_outlined,
                            size: 20,
                            color: AppTheme.accent,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Erinnerung am',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: context.appTextTertiary,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _formatExact(_remindAt),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: context.appTextPrimary,
                                  ),
                                ),
                                if (rel != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    rel,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: AppTheme.accent,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Icon(
                            Icons.edit_calendar_outlined,
                            size: 18,
                            color: context.appTextTertiary,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // Create button (Material FilledButton style)
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _loading || _titleCtrl.text.trim().isEmpty
                        ? null
                        : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      disabledBackgroundColor: AppTheme.accent.withValues(
                        alpha: 0.4,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: _loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.add_alert_outlined,
                            color: Colors.white,
                          ),
                    label: Text(
                      _loading ? 'Wird erstellt…' : 'Erinnerung erstellen',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Cupertino-native text field — used inside showCupertinoModalPopup where no
// Material ancestor exists and TextField would crash.
class _CupertinoField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String placeholder;
  final int maxLines;
  final VoidCallback? onChanged;

  const _CupertinoField({
    required this.controller,
    required this.label,
    required this.placeholder,
    required this.maxLines,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: context.appTextTertiary,
          ),
        ),
        const SizedBox(height: 6),
        CupertinoTextField(
          controller: controller,
          maxLines: maxLines,
          placeholder: placeholder,
          placeholderStyle: TextStyle(color: context.appTextTertiary),
          style: TextStyle(fontSize: 15, color: context.appTextPrimary),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: context.appCard,
            borderRadius: BorderRadius.circular(12),
          ),
          autocorrect: false,
          enableSuggestions: false,
          spellCheckConfiguration: const SpellCheckConfiguration.disabled(),
          onChanged: onChanged != null ? (_) => onChanged!() : null,
        ),
      ],
    );
  }
}

// ── Members sheet ─────────────────────────────────────────────────────────────

class _MembersSheet extends StatefulWidget {
  final ClassRoom cls;
  const _MembersSheet({required this.cls});

  @override
  State<_MembersSheet> createState() => _MembersSheetState();
}

class _MembersSheetState extends State<_MembersSheet> {
  Map<String, String>? _names;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // memberNames already contains stableUid → displayName from Firestore
    final names = Map<String, String>.from(widget.cls.memberNames);
    // Fallback: if a member has no name entry, use their stableUid
    for (final uid in widget.cls.members) {
      names.putIfAbsent(uid, () => uid);
    }
    if (mounted) setState(() => _names = names);
  }

  @override
  Widget build(BuildContext context) {
    final cls = widget.cls;
    final myStableUid = AuthService.instance.stableUid;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: context.appBorder.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  _isIOS ? CupertinoIcons.person_2_fill : Icons.group,
                  size: 18,
                  color: AppTheme.accent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${cls.name} – Mitglieder',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: context.appTextPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${cls.members.length} ${cls.members.length == 1 ? "Mitglied" : "Mitglieder"}',
              style: TextStyle(fontSize: 13, color: context.appTextSecondary),
            ),
            const SizedBox(height: 14),
            if (_names == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Center(child: CupertinoActivityIndicator(radius: 12)),
              )
            else
              ...cls.members.map((uid) {
                final name = _names![uid] ?? uid;
                final isMe = uid == myStableUid;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.accent.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accent,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: context.appTextPrimary,
                          ),
                        ),
                      ),
                      if (isMe)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            'Du',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.accent,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

// ── Toast ─────────────────────────────────────────────────────────────────────

class _ToastOverlay extends StatefulWidget {
  final String message;
  const _ToastOverlay({required this.message});

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) _ctrl.reverse();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 80,
      left: 40,
      right: 40,
      child: FadeTransition(
        opacity: _opacity,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: context.appSurface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            widget.message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.appTextPrimary,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Reminder Detail Sheet ─────────────────────────────────────────────────────

class _ReminderDetailSheet extends StatefulWidget {
  final Reminder reminder;
  final String? myStableUid;
  final bool isAdmin;
  final VoidCallback onDelete;

  const _ReminderDetailSheet({
    required this.reminder,
    required this.myStableUid,
    required this.isAdmin,
    required this.onDelete,
  });

  @override
  State<_ReminderDetailSheet> createState() => _ReminderDetailSheetState();
}

class _ReminderDetailSheetState extends State<_ReminderDetailSheet> {
  List<ApiComment> _comments = [];
  bool _commentsLoading = true;

  @override
  void initState() {
    super.initState();
    _loadComments();
  }

  Future<void> _loadComments() async {
    try {
      final comments = await ApiClient.instance.getReminderComments(
        widget.reminder.classId,
        widget.reminder.id,
      );
      if (mounted) setState(() { _comments = comments; _commentsLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _commentsLoading = false);
    }
  }

  String _formatRemindAt(DateTime dt) {
    final weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '${weekdays[dt.weekday - 1]}, ${pad2(dt.day)}.${pad2(dt.month)} · ${pad2(dt.hour)}:${pad2(dt.minute)} Uhr';
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.reminder;
    final isDue = r.isDue;
    final statusColor = isDue ? AppTheme.warning : AppTheme.accent;
    final isMine = widget.myStableUid != null && r.createdByUid == widget.myStableUid;
    final canDelete = isMine || widget.isAdmin;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      snap: true,
      shouldCloseOnMinExtent: true,
      builder: (_, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: context.appBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Container(
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: context.appTextTertiary.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),

              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: statusColor.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              isDue
                                  ? (_isIOS ? CupertinoIcons.bell_fill : Icons.notifications_active)
                                  : (_isIOS ? CupertinoIcons.clock : Icons.access_time_rounded),
                              size: 20,
                              color: statusColor,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.title,
                                  style: TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                    color: context.appTextPrimary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  _formatRemindAt(r.remindAt),
                                  style: TextStyle(fontSize: 13, color: statusColor),
                                ),
                              ],
                            ),
                          ),
                          if (canDelete)
                            GestureDetector(
                              onTap: () {
                                Navigator.pop(context);
                                widget.onDelete();
                              },
                              child: Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Icon(
                                  _isIOS ? CupertinoIcons.trash : Icons.delete_outline,
                                  size: 20,
                                  color: AppTheme.danger,
                                ),
                              ),
                            ),
                        ],
                      ),

                      if (r.body.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          r.body,
                          style: TextStyle(
                            fontSize: 15,
                            color: context.appTextSecondary,
                            height: 1.4,
                          ),
                        ),
                      ],

                      const SizedBox(height: 6),
                      Text(
                        'von ${r.createdByUsername.isNotEmpty ? r.createdByUsername : r.createdByName}',
                        style: TextStyle(fontSize: 12, color: context.appTextTertiary),
                      ),

                      const SizedBox(height: 20),
                      Divider(height: 1, color: context.appBorder.withValues(alpha: 0.3)),
                      const SizedBox(height: 20),

                      // Comments
                      _ReminderCommentSection(
                        comments: _comments,
                        loading: _commentsLoading,
                        myStableUid: widget.myStableUid,
                        isAdmin: widget.isAdmin,
                        onAdd: (body) async {
                          final c = await ApiClient.instance.createReminderComment(
                            r.classId,
                            r.id,
                            body,
                          );
                          if (mounted) setState(() => _comments = [..._comments, c]);
                        },
                        onDelete: (commentId) async {
                          await ApiClient.instance.deleteReminderComment(
                            r.classId,
                            r.id,
                            commentId,
                          );
                          if (mounted) setState(() => _comments = _comments.where((c) => c.id != commentId).toList());
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Reminder Comment Section ──────────────────────────────────────────────────

class _ReminderCommentSection extends StatefulWidget {
  final List<ApiComment> comments;
  final bool loading;
  final String? myStableUid;
  final bool isAdmin;
  final Future<void> Function(String body) onAdd;
  final Future<void> Function(String commentId) onDelete;

  const _ReminderCommentSection({
    required this.comments,
    required this.loading,
    required this.myStableUid,
    required this.isAdmin,
    required this.onAdd,
    required this.onDelete,
  });

  @override
  State<_ReminderCommentSection> createState() => _ReminderCommentSectionState();
}

class _ReminderCommentSectionState extends State<_ReminderCommentSection> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _formatTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Gerade eben';
    if (diff.inMinutes < 60) return 'vor ${diff.inMinutes} Min.';
    if (diff.inHours < 24) return 'vor ${diff.inHours} Std.';
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    return '$d.$m.${dt.year}';
  }

  Future<void> _submit() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await widget.onAdd(text);
      _ctrl.clear();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Kommentare',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: context.appTextPrimary,
          ),
        ),
        const SizedBox(height: 12),

        if (widget.loading)
          Center(child: CupertinoActivityIndicator(radius: 10))
        else if (widget.comments.isEmpty)
          Text(
            'Noch keine Kommentare.',
            style: TextStyle(fontSize: 13, color: context.appTextTertiary),
          )
        else
          ...widget.comments.map((c) {
            final isMine = c.stableUid == widget.myStableUid;
            final canDelete = isMine || widget.isAdmin;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _ReminderCommentAvatar(username: c.username),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              c.username,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: context.appTextPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _formatTime(c.createdAt),
                              style: TextStyle(fontSize: 11, color: context.appTextTertiary),
                            ),
                            if (canDelete) ...[
                              const Spacer(),
                              GestureDetector(
                                onTap: () => widget.onDelete(c.id),
                                child: Icon(
                                  _isIOS ? CupertinoIcons.trash : Icons.delete_outline,
                                  size: 14,
                                  color: context.appTextTertiary,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          c.body,
                          style: TextStyle(fontSize: 14, color: context.appTextSecondary, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),

        const SizedBox(height: 16),

        // Input row
        Row(
          children: [
            Expanded(
              child: CupertinoTextField(
                controller: _ctrl,
                placeholder: 'Kommentar schreiben…',
                placeholderStyle: TextStyle(fontSize: 14, color: context.appTextTertiary),
                style: TextStyle(fontSize: 14, color: context.appTextPrimary),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: context.appSurface,
                  borderRadius: BorderRadius.circular(12),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: _submit,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.accent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _sending
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: CupertinoActivityIndicator(color: Colors.white, radius: 10),
                      )
                    : const Icon(CupertinoIcons.arrow_up, size: 20, color: Colors.white),
              ),
            ),
          ],
        ),
      ],
      ),
    );
  }
}

class _ReminderCommentAvatar extends StatelessWidget {
  final String username;
  const _ReminderCommentAvatar({required this.username});

  @override
  Widget build(BuildContext context) {
    final hash = username.codeUnits.fold(0, (h, c) => (h * 31 + c) & 0xFFFFFFFF);
    final hue = (hash % 360).toDouble();
    final color = HSLColor.fromAHSL(1.0, hue, 0.45, 0.50).toColor();
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.15),
      ),
      child: Center(
        child: Text(
          username.isNotEmpty ? username[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}
