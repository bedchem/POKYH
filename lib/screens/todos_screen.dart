import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/reminder_service.dart';
import '../services/todo_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_message.dart';

bool get _isIOS => Platform.isIOS;

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class TodosScreen extends StatefulWidget {
  const TodosScreen({super.key});

  @override
  State<TodosScreen> createState() => _TodosScreenState();
}

class _TodosScreenState extends State<TodosScreen> {
  Stream<List<Todo>>? _stream;
  bool _initDone = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await ReminderService().initialize();
    if (AuthService.instance.stableUid == null) {
      await AuthService.instance.resolveStableUid();
    }
    await TodoService().cleanupDoneTodos();
    if (mounted) {
      setState(() {
        _stream = TodoService().todoStream();
        _initDone = true;
      });
    }
  }

  void _openSheet({Todo? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.appSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _TodoSheet(existing: existing),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ──
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(
                children: [
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
                  const SizedBox(width: 12),
                  Text(
                    'Todos',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      color: context.appTextPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => _openSheet(),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppTheme.accentSoft.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.add,
                        size: 20,
                        color: AppTheme.accentSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── List ──
            Expanded(
              child: !_initDone
                  ? const Center(child: CupertinoActivityIndicator())
                  : StreamBuilder<List<Todo>>(
                      stream: _stream,
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(CupertinoIcons.exclamationmark_circle_fill,
                                      color: Colors.red, size: 40),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Fehler beim Laden der Todos:\n${snap.error}',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: context.appTextSecondary),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        if (snap.connectionState ==
                                ConnectionState.waiting &&
                            !snap.hasData) {
                          return const Center(
                            child: CupertinoActivityIndicator(),
                          );
                        }
                        final todos = snap.data ?? [];
                        if (todos.isEmpty) {
                          return _EmptyState(onAdd: () => _openSheet());
                        }

                        final open =
                            todos.where((t) => !t.isDone).toList();
                        final done =
                            todos.where((t) => t.isDone).toList();

                        return ListView(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          children: [
                            if (open.isNotEmpty) ...[
                              _sectionLabel(
                                context,
                                '${open.length} offen',
                              ),
                              ...open.map(
                                (t) => _TodoTile(
                                  todo: t,
                                  onTap: () => _openSheet(existing: t),
                                  onToggle: () => TodoService().toggleDone(
                                    t.id,
                                    !t.isDone,
                                  ),
                                  onDelete: () =>
                                      TodoService().deleteTodo(t.id),
                                ),
                              ),
                            ],
                            if (done.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              _sectionLabel(context, 'Erledigt'),
                              ...done.map(
                                (t) => _TodoTile(
                                  todo: t,
                                  onTap: () => _openSheet(existing: t),
                                  onToggle: () => TodoService().toggleDone(
                                    t.id,
                                    !t.isDone,
                                  ),
                                  onDelete: () =>
                                      TodoService().deleteTodo(t.id),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: context.appTextTertiary,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppTheme.accentSoft.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check_circle_outline_rounded,
              size: 36,
              color: AppTheme.accentSoft,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Keine Todos',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: context.appTextPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tippe auf + um ein Todo hinzuzufügen',
            style: TextStyle(
              fontSize: 14,
              color: context.appTextTertiary,
            ),
          ),
          const SizedBox(height: 28),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24, vertical: 12,
              ),
              decoration: BoxDecoration(
                color: AppTheme.accentSoft.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Erstes Todo erstellen',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accentSoft,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Todo Tile
// ─────────────────────────────────────────────────────────────────────────────

class _TodoTile extends StatelessWidget {
  final Todo todo;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _TodoTile({
    required this.todo,
    required this.onTap,
    required this.onToggle,
    required this.onDelete,
  });

  String _formatRemind(DateTime dt) {
    final weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final now = DateTime.now();
    final isToday = dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day;
    String pad2(int n) => n.toString().padLeft(2, '0');
    final time = '${pad2(dt.hour)}:${pad2(dt.minute)}';
    return isToday ? 'Heute · $time' : '${weekdays[dt.weekday - 1]} · $time';
  }

  @override
  Widget build(BuildContext context) {
    final isPast =
        todo.remindAt != null && todo.remindAt!.isBefore(DateTime.now());
    return Dismissible(
      key: Key(todo.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDelete(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: AppTheme.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(
          CupertinoIcons.trash,
          color: AppTheme.danger,
          size: 18,
        ),
      ),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          decoration: BoxDecoration(
            color: context.appSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: todo.isDone
                  ? context.appBorder.withValues(alpha: 0.1)
                  : context.appBorder.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Checkbox
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggle,
                child: Padding(
                  padding: const EdgeInsets.only(top: 1, right: 12),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: todo.isDone
                          ? AppTheme.accentSoft
                          : Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: todo.isDone
                            ? AppTheme.accentSoft
                            : context.appBorder,
                        width: 2,
                      ),
                    ),
                    child: todo.isDone
                        ? const Icon(
                            Icons.check,
                            size: 13,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
              ),
              // Text content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      todo.title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: todo.isDone
                            ? context.appTextTertiary
                            : context.appTextPrimary,
                        decoration: todo.isDone
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: context.appTextTertiary,
                      ),
                    ),
                    if (todo.description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        todo.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.appTextTertiary,
                          height: 1.3,
                        ),
                      ),
                    ],
                    if (todo.remindAt != null && !todo.isDone) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isPast
                              ? AppTheme.danger.withValues(alpha: 0.1)
                              : AppTheme.accentSoft.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isIOS
                                  ? CupertinoIcons.bell_fill
                                  : Icons.notifications_rounded,
                              size: 11,
                              color: isPast
                                  ? AppTheme.danger
                                  : AppTheme.accentSoft,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              _formatRemind(todo.remindAt!),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isPast
                                    ? AppTheme.danger
                                    : AppTheme.accentSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Chevron
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 8),
                child: Icon(
                  _isIOS
                      ? CupertinoIcons.chevron_right
                      : Icons.chevron_right,
                  size: 14,
                  color: context.appTextTertiary.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Add / Edit Sheet
// ─────────────────────────────────────────────────────────────────────────────

class _TodoSheet extends StatefulWidget {
  final Todo? existing;
  const _TodoSheet({this.existing});

  @override
  State<_TodoSheet> createState() => _TodoSheetState();
}

class _TodoSheetState extends State<_TodoSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  DateTime? _remindAt;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.existing?.title ?? '');
    _descCtrl =
        TextEditingController(text: widget.existing?.description ?? '');
    _remindAt = widget.existing?.remindAt;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  bool get _isEdit => widget.existing != null;

  Future<void> _pickDateTime() async {
    if (_isIOS) {
      DateTime picked = _remindAt ??
          DateTime.now().add(const Duration(hours: 1));
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
                  initialDateTime:
                      _remindAt ??
                      DateTime.now().add(const Duration(hours: 1)),
                  minimumDate: DateTime.now().add(
                    const Duration(minutes: 1),
                  ),
                  use24hFormat: true,
                  onDateTimeChanged: (dt) => picked = dt,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      final date = await showDatePicker(
        context: context,
        initialDate:
            _remindAt ?? DateTime.now().add(const Duration(hours: 1)),
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        builder: (ctx, child) => Theme(
          data: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppTheme.accentSoft,
              brightness: Theme.of(context).brightness,
            ),
          ),
          child: child!,
        ),
      );
      if (date == null || !mounted) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(
          _remindAt ?? DateTime.now().add(const Duration(hours: 1)),
        ),
        builder: (ctx, child) => Theme(
          data: ThemeData(
            colorScheme: ColorScheme.fromSeed(
              seedColor: AppTheme.accentSoft,
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
  }

  Future<void> _delete() async {
    setState(() => _saving = true);
    await TodoService().deleteTodo(widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _save() async {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return;
    setState(() => _saving = true);
    try {
      final desc = _descCtrl.text.trim();
      if (_isEdit) {
        final prev = widget.existing!;
        final clearRemind =
            prev.remindAt != null && _remindAt == null;
        await TodoService().updateTodo(
          prev.id,
          title: title,
          description: desc,
          remindAt: _remindAt,
          clearRemindAt: clearRemind,
        );
      } else {
        await TodoService().addTodo(
          title: title,
          description: desc,
          remindAt: _remindAt,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      final msg = simplifyErrorMessage(e);
      if (_isIOS) {
        showCupertinoDialog(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: const Text('Fehler'),
            content: Text(msg),
            actions: [
              CupertinoDialogAction(
                isDefaultAction: true,
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          ),
        );
      }
    }
  }

  String _formatRemind(DateTime dt) {
    final weekdays = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    String pad2(int n) => n.toString().padLeft(2, '0');
    return '${weekdays[dt.weekday - 1]}, ${pad2(dt.day)}.${pad2(dt.month)}.${dt.year}  ${pad2(dt.hour)}:${pad2(dt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        0, 0, 0, MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
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
            const SizedBox(height: 18),
            // Title
            Text(
              _isEdit ? 'Bearbeiten' : 'Neues Todo',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: context.appTextPrimary,
              ),
            ),
            const SizedBox(height: 20),

            // Titel field
            _fieldLabel(context, 'Titel'),
            const SizedBox(height: 6),
            _isIOS
                ? CupertinoTextField(
                    controller: _titleCtrl,
                    placeholder: 'z.B. Mathe Hausaufgabe',
                    placeholderStyle: TextStyle(
                      color: context.appTextTertiary,
                    ),
                    style: TextStyle(
                      fontSize: 15,
                      color: context.appTextPrimary,
                    ),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.appCard,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    autocorrect: false,
                    enableSuggestions: false,
                    spellCheckConfiguration:
                        const SpellCheckConfiguration.disabled(),
                    autofocus: !_isEdit,
                  )
                : TextField(
                    controller: _titleCtrl,
                    autofocus: !_isEdit,
                    style: TextStyle(
                      fontSize: 15,
                      color: context.appTextPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'z.B. Mathe Hausaufgabe',
                      hintStyle: TextStyle(color: context.appTextTertiary),
                      filled: true,
                      fillColor: context.appCard,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
            const SizedBox(height: 14),

            // Beschreibung field
            _fieldLabel(context, 'Beschreibung (optional)'),
            const SizedBox(height: 6),
            _isIOS
                ? CupertinoTextField(
                    controller: _descCtrl,
                    placeholder: 'Weitere Details…',
                    placeholderStyle: TextStyle(
                      color: context.appTextTertiary,
                    ),
                    style: TextStyle(
                      fontSize: 15,
                      color: context.appTextPrimary,
                    ),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: context.appCard,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    maxLines: 3,
                    autocorrect: false,
                    enableSuggestions: false,
                    spellCheckConfiguration:
                        const SpellCheckConfiguration.disabled(),
                  )
                : TextField(
                    controller: _descCtrl,
                    maxLines: 3,
                    style: TextStyle(
                      fontSize: 15,
                      color: context.appTextPrimary,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Weitere Details…',
                      hintStyle: TextStyle(color: context.appTextTertiary),
                      filled: true,
                      fillColor: context.appCard,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
            const SizedBox(height: 14),

            // Erinnerung row
            _fieldLabel(context, 'Erinnerung (optional)'),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: _pickDateTime,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 13,
                ),
                decoration: BoxDecoration(
                  color: context.appCard,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isIOS
                          ? CupertinoIcons.bell
                          : Icons.notifications_outlined,
                      size: 18,
                      color: _remindAt != null
                          ? AppTheme.accentSoft
                          : context.appTextTertiary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _remindAt != null
                            ? _formatRemind(_remindAt!)
                            : 'Keine Erinnerung',
                        style: TextStyle(
                          fontSize: 14,
                          color: _remindAt != null
                              ? context.appTextPrimary
                              : context.appTextTertiary,
                        ),
                      ),
                    ),
                    if (_remindAt != null)
                      GestureDetector(
                        onTap: () => setState(() => _remindAt = null),
                        child: Icon(
                          _isIOS
                              ? CupertinoIcons.xmark_circle_fill
                              : Icons.cancel,
                          size: 18,
                          color: context.appTextTertiary,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Speichern button
            SizedBox(
              width: double.infinity,
              child: _isIOS
                  ? CupertinoButton(
                      color: AppTheme.accentSoft,
                      borderRadius: BorderRadius.circular(14),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const CupertinoActivityIndicator(
                              color: Colors.white,
                            )
                          : const Text(
                              'Speichern',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    )
                  : FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.accentSoft,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Speichern',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                    ),
            ),
            if (_isEdit) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: _isIOS
                    ? CupertinoButton(
                        color: AppTheme.danger.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        onPressed: _saving ? null : _delete,
                        child: const Text(
                          'Löschen',
                          style: TextStyle(
                            color: AppTheme.danger,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                            color: AppTheme.danger.withValues(alpha: 0.4),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 15),
                        ),
                        onPressed: _saving ? null : _delete,
                        child: const Text(
                          'Löschen',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.danger,
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

  Widget _fieldLabel(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.3,
        color: context.appTextTertiary,
      ),
    );
  }
}
