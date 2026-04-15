import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/webuntis_service.dart';
import '../theme/app_theme.dart';

class MessageDetailScreen extends StatefulWidget {
  final WebUntisService service;
  final MessagePreview message;

  const MessageDetailScreen({
    super.key,
    required this.service,
    required this.message,
  });

  @override
  State<MessageDetailScreen> createState() => _MessageDetailScreenState();
}

class _MessageDetailScreenState extends State<MessageDetailScreen> {
  MessageDetail? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  Future<void> _loadDetail() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final detail = await widget.service.getMessageDetail(widget.message.id);
      if (mounted) {
        setState(() {
          _detail = detail;
          _loading = false;
        });
      }
      // Mark as read in background
      if (!widget.message.isRead) {
        widget.service.markMessageAsRead(widget.message.id);
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
          _error = '$e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
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
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        CupertinoIcons.back,
                        color: AppTheme.textPrimary,
                        size: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Nachricht',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                        letterSpacing: -0.4,
                      ),
                    ),
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
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(
        child: CupertinoActivityIndicator(radius: 14),
      );
    }

    if (_error != null) {
      // Show preview data even if detail fetch fails
      return _buildFallbackContent();
    }

    final detail = _detail!;
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subject
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.subject.isNotEmpty
                      ? detail.subject
                      : '(Kein Betreff)',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 12),

                // Sender info
                Row(
                  children: [
                    _SenderAvatar(name: detail.senderName),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detail.senderName.isNotEmpty
                                ? detail.senderName
                                : 'Unbekannt',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            detail.sentDateFormatted,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Body
          if (detail.body.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: SelectableText(
                detail.body,
                style: TextStyle(
                  fontSize: 15,
                  color: AppTheme.textPrimary,
                  height: 1.5,
                ),
              ),
            ),

          // Attachments
          if (detail.attachments.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Anhänge',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final attachment in detail.attachments)
                    _AttachmentTile(
                      attachment: attachment,
                      service: widget.service,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFallbackContent() {
    final msg = widget.message;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg.subject.isNotEmpty ? msg.subject : '(Kein Betreff)',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _SenderAvatar(name: msg.senderName),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            msg.senderName.isNotEmpty
                                ? msg.senderName
                                : 'Unbekannt',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            msg.sentDateFormatted,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Error banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(
                  CupertinoIcons.exclamationmark_triangle_fill,
                  color: AppTheme.warning,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _error ?? 'Nachricht konnte nicht vollständig geladen werden.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (msg.contentPreview.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                msg.contentPreview,
                style: TextStyle(
                  fontSize: 15,
                  color: AppTheme.textPrimary,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Sender Avatar ────────────────────────────────────────────────────────────

class _SenderAvatar extends StatelessWidget {
  final String name;

  const _SenderAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final hash = name.codeUnits.fold(0, (h, c) => (h * 31 + c) & 0xFFFFFFFF);
    final hue = (hash % 360).toDouble();
    final color = HSLColor.fromAHSL(1.0, hue, 0.45, 0.50).toColor();

    return Container(
      width: 36,
      height: 36,
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
            fontSize: 15,
          ),
        ),
      ),
    );
  }
}

// ── Attachment Tile ──────────────────────────────────────────────────────────

class _AttachmentTile extends StatelessWidget {
  final MessageAttachment attachment;
  final WebUntisService service;

  const _AttachmentTile({required this.attachment, required this.service});

  IconData get _icon {
    final name = attachment.name.toLowerCase();
    if (name.endsWith('.pdf')) return CupertinoIcons.doc_fill;
    if (name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.gif')) {
      return CupertinoIcons.photo_fill;
    }
    if (name.endsWith('.doc') || name.endsWith('.docx')) {
      return CupertinoIcons.doc_text_fill;
    }
    if (name.endsWith('.xls') || name.endsWith('.xlsx')) {
      return CupertinoIcons.table_fill;
    }
    return CupertinoIcons.paperclip;
  }

  void _openAttachment(BuildContext context) async {
    final url = attachment.url;
    if (url == null || url.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Anhang kann nicht geöffnet werden'),
            backgroundColor: AppTheme.danger,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        );
      }
      return;
    }

    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _openAttachment(context),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(_icon, size: 20, color: AppTheme.accent),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    attachment.name,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (attachment.size != null) ...[
                  const SizedBox(width: 8),
                  Text(
                    _formatSize(attachment.size!),
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
                const SizedBox(width: 4),
                Icon(
                  CupertinoIcons.arrow_down_circle,
                  size: 16,
                  color: AppTheme.textTertiary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
