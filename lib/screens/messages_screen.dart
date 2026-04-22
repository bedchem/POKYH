import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/webuntis_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_message.dart';
import 'message_detail_screen.dart';

class MessagesScreen extends StatefulWidget {
  final WebUntisService service;
  const MessagesScreen({super.key, required this.service});

  @override
  State<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends State<MessagesScreen> {
  List<MessagePreview> _messages = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool force = false}) async {
    if (!force && !_loading) setState(() => _loading = true);
    try {
      final messages = await widget.service.getMessages(forceRefresh: force);
      if (mounted) {
        setState(() {
          _messages = messages;
          _loading = false;
          _error = null;
        });
      }
    } on WebUntisException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = simplifyErrorMessage(e);
          _loading = false;
        });
      }
    }
  }

  void _openMessage(MessagePreview message) async {
    await Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) =>
            MessageDetailScreen(service: widget.service, message: message),
      ),
    );
    // Refresh to update read status
    if (mounted) {
      setState(() {
        _messages = widget.service.cachedMessages ?? _messages;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBg,
      body: ClipRect(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: context.appSurface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          CupertinoIcons.back,
                          color: context.appTextPrimary,
                          size: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Mitteilungen',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          color: context.appTextPrimary,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    if (!_loading)
                      _UnreadBadgeChip(
                        count: _messages.where((m) => !m.isRead).length,
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Content
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_loading && _messages.isEmpty) {
      return const Center(child: CupertinoActivityIndicator(radius: 14));
    }

    if (_error != null && _messages.isEmpty) {
      return _ErrorView(message: _error!, onRetry: () => _load(force: true));
    }

    if (_messages.isEmpty) {
      return _EmptyView();
    }

    return RefreshIndicator(
      color: AppTheme.accent,
      backgroundColor: context.appSurface,
      onRefresh: () => _load(force: true),
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _messages.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final msg = _messages[index];
          return _MessageTile(message: msg, onTap: () => _openMessage(msg));
        },
      ),
    );
  }
}

// ── Message Tile ─────────────────────────────────────────────────────────────

class _MessageTile extends StatelessWidget {
  final MessagePreview message;
  final VoidCallback onTap;

  const _MessageTile({required this.message, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.appSurface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Unread indicator + avatar
              Column(
                children: [
                  const SizedBox(height: 2),
                  _SenderAvatar(
                    name: message.senderName,
                    isRead: message.isRead,
                  ),
                ],
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sender + date
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            message.senderName.isNotEmpty
                                ? message.senderName
                                : 'Unbekannt',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: message.isRead
                                  ? FontWeight.w400
                                  : FontWeight.w600,
                              color: context.appTextPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          message.sentDateFormatted,
                          style: TextStyle(
                            fontSize: 12,
                            color: message.isRead
                                ? context.appTextTertiary
                                : AppTheme.accent,
                            fontWeight: message.isRead
                                ? FontWeight.w400
                                : FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),

                    // Subject
                    Text(
                      message.subject.isNotEmpty
                          ? message.subject
                          : '(Kein Betreff)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: message.isRead
                            ? FontWeight.w400
                            : FontWeight.w600,
                        color: context.appTextPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),

                    // Preview
                    if (message.contentPreview.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        message.contentPreview,
                        style: TextStyle(
                          fontSize: 13,
                          color: context.appTextSecondary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],

                    // Attachment indicator
                    if (message.hasAttachments) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.paperclip,
                            size: 12,
                            color: context.appTextTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Anhang',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.appTextTertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              // Chevron
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 4),
                child: Icon(
                  CupertinoIcons.chevron_right,
                  size: 14,
                  color: context.appTextTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Sender Avatar ────────────────────────────────────────────────────────────

class _SenderAvatar extends StatelessWidget {
  final String name;
  final bool isRead;

  const _SenderAvatar({required this.name, required this.isRead});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    // Deterministic color from name
    final hash = name.codeUnits.fold(0, (h, c) => (h * 31 + c) & 0xFFFFFFFF);
    final hue = (hash % 360).toDouble();
    final color = HSLColor.fromAHSL(1.0, hue, 0.45, 0.50).toColor();

    return Stack(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.15),
          ),
          child: Center(
            child: Text(
              initial,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
          ),
        ),
        if (!isRead)
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.accent,
                border: Border.all(color: context.appSurface, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Unread Badge Chip ────────────────────────────────────────────────────────

class _UnreadBadgeChip extends StatelessWidget {
  final int count;
  const _UnreadBadgeChip({required this.count});

  @override
  Widget build(BuildContext context) {
    if (count == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count ungelesen',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppTheme.accent,
        ),
      ),
    );
  }
}

// ── Empty View ───────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.mail, size: 48, color: context.appTextTertiary),
          const SizedBox(height: 12),
          Text(
            'Keine Mitteilungen',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: context.appTextSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Neue Nachrichten erscheinen hier',
            style: TextStyle(fontSize: 13, color: context.appTextTertiary),
          ),
        ],
      ),
    );
  }
}

// ── Error View ───────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.danger.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  CupertinoIcons.exclamationmark_triangle_fill,
                  color: AppTheme.danger,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.appTextSecondary, fontSize: 14),
            ),
            const SizedBox(height: 18),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              color: AppTheme.accent,
              borderRadius: BorderRadius.circular(9),
              minimumSize: Size.zero,
              onPressed: onRetry,
              child: const Text(
                'Erneut versuchen',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
