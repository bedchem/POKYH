import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/webuntis_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_message.dart';
import '../widgets/back_swipe_pop_scope.dart';

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

  // Attachment state — filled from the detail response or a fallback call.
  // null  = not yet attempted
  // []    = attempted, nothing found (but we still show UI if hasAttachments=true)
  // [...] = loaded successfully
  List<MessageAttachment>? _attachments;
  bool _attachmentsLoading = false;
  bool _attachmentsFetchFailed = false;

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
      if (!mounted) return;

      setState(() {
        _detail = detail;
        _loading = false;
        // Use attachments from detail if present.
        if (detail.attachments.isNotEmpty) {
          _attachments = detail.attachments;
        }
      });

      // Mark as read in background.
      if (!widget.message.isRead) {
        widget.service.markMessageAsRead(widget.message.id);
      }

      // Fallback: if detail had no attachments but the list view showed the
      // paperclip icon, fetch them from a dedicated endpoint.
      if (detail.attachments.isEmpty && widget.message.hasAttachments) {
        _fetchAttachmentsFallback();
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

  Future<void> _fetchAttachmentsFallback() async {
    if (!mounted) return;
    setState(() {
      _attachmentsLoading = true;
      _attachmentsFetchFailed = false;
    });
    try {
      final list = await widget.service.getMessageAttachments(
        widget.message.id,
      );
      if (!mounted) return;
      if (list.isNotEmpty) {
        setState(() {
          _attachments = list;
          _attachmentsLoading = false;
        });
      } else {
        // API returned nothing — keep the section visible because
        // widget.message.hasAttachments guarantees an attachment exists.
        setState(() {
          _attachmentsLoading = false;
          _attachmentsFetchFailed = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _attachmentsLoading = false;
          _attachmentsFetchFailed = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final page = Scaffold(
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
                      'Nachricht',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: context.appTextPrimary,
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

    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;
    if (isIOS) return page;

    return BackSwipePopScope(
      canPop: () => Navigator.of(context).canPop(),
      child: page,
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return const Center(child: CupertinoActivityIndicator(radius: 14));
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
              color: context.appSurface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.subject.isNotEmpty ? detail.subject : '(Kein Betreff)',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: context.appTextPrimary,
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
                              color: context.appTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            detail.sentDateFormatted,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.appTextSecondary,
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

          // Body + Attachments in one card (mail-app style)
          _buildBodyCard(detail),
        ],
      ),
    );
  }

  Widget _buildBodyCard(MessageDetail detail) {
    final attachments = _attachments ?? const <MessageAttachment>[];
    // Show attachment section when:
    //  - we have loaded attachments, OR
    //  - we are loading, OR
    //  - message is known to have attachments (even if metadata fetch failed)
    final showAttachmentSection =
        attachments.isNotEmpty ||
        _attachmentsLoading ||
        (widget.message.hasAttachments &&
            (_attachmentsFetchFailed || _attachments == null));

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Body text
          if (detail.body.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                showAttachmentSection ? 12 : 16,
              ),
              child: _BodyWithLinks(body: detail.body),
            ),

          // Attachment section
          if (showAttachmentSection) ...[
            if (detail.body.isNotEmpty)
              Divider(
                height: 1,
                thickness: 0.5,
                color: context.appBorder.withValues(alpha: 0.5),
              ),

            // Header row
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Row(
                children: [
                  Icon(
                    CupertinoIcons.paperclip,
                    size: 13,
                    color: context.appTextTertiary,
                  ),
                  const SizedBox(width: 5),
                  if (_attachmentsLoading)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 10,
                          height: 10,
                          child: CupertinoActivityIndicator(radius: 5),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Anhänge werden geladen…',
                          style: TextStyle(
                            fontSize: 12,
                            color: context.appTextTertiary,
                          ),
                        ),
                      ],
                    )
                  else if (attachments.isNotEmpty)
                    Text(
                      '${attachments.length} '
                      '${attachments.length == 1 ? 'Anhang' : 'Anhänge'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.appTextTertiary,
                        letterSpacing: 0.2,
                      ),
                    )
                  else
                    Text(
                      'Anhang vorhanden',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: context.appTextTertiary,
                        letterSpacing: 0.2,
                      ),
                    ),
                ],
              ),
            ),

            // Attachment tiles
            if (attachments.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  children: [
                    for (final a in attachments)
                      _AttachmentTile(
                        attachment: a,
                        service: widget.service,
                        // Preview ID is always known; detail payload may omit/zero id.
                        messageId: widget.message.id,
                      ),
                  ],
                ),
              ),

            // Retry button when metadata fetch failed
            if (_attachmentsFetchFailed &&
                attachments.isEmpty &&
                !_attachmentsLoading)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Material(
                  color: context.appBg,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: _fetchAttachmentsFallback,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppTheme.accent.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              CupertinoIcons.arrow_down_circle,
                              size: 22,
                              color: AppTheme.accent,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Anhang laden',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: AppTheme.accent,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Tippen zum erneuten Laden',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.appTextTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            CupertinoIcons.refresh,
                            size: 18,
                            color: AppTheme.accent,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            if (_attachmentsLoading ||
                (attachments.isEmpty && !_attachmentsFetchFailed))
              const SizedBox(height: 8),
          ],

          if (detail.body.isEmpty && !showAttachmentSection)
            const SizedBox(height: 16),
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
              color: context.appSurface,
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
                    color: context.appTextPrimary,
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
                              color: context.appTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            msg.sentDateFormatted,
                            style: TextStyle(
                              fontSize: 12,
                              color: context.appTextSecondary,
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
                    _error ??
                        'Nachricht konnte nicht vollständig geladen werden.',
                    style: TextStyle(
                      fontSize: 13,
                      color: context.appTextSecondary,
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
                color: context.appSurface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Text(
                msg.contentPreview,
                style: TextStyle(
                  fontSize: 15,
                  color: context.appTextPrimary,
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

class _AttachmentTile extends StatefulWidget {
  final MessageAttachment attachment;
  final WebUntisService service;
  final int messageId;

  const _AttachmentTile({
    required this.attachment,
    required this.service,
    required this.messageId,
  });

  @override
  State<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<_AttachmentTile> {
  bool _downloading = false;

  // Returns icon + background colour based on file extension (mail-app style).
  ({IconData icon, Color color}) get _fileStyle {
    final n = widget.attachment.name.toLowerCase();
    if (n.endsWith('.pdf')) {
      return (icon: CupertinoIcons.doc_fill, color: const Color(0xFFE53935));
    }
    if (n.endsWith('.jpg') ||
        n.endsWith('.jpeg') ||
        n.endsWith('.png') ||
        n.endsWith('.gif') ||
        n.endsWith('.webp') ||
        n.endsWith('.heic')) {
      return (icon: CupertinoIcons.photo_fill, color: const Color(0xFF1E88E5));
    }
    if (n.endsWith('.doc') || n.endsWith('.docx')) {
      return (
        icon: CupertinoIcons.doc_text_fill,
        color: const Color(0xFF1565C0),
      );
    }
    if (n.endsWith('.xls') || n.endsWith('.xlsx')) {
      return (icon: CupertinoIcons.table_fill, color: const Color(0xFF2E7D32));
    }
    if (n.endsWith('.ppt') || n.endsWith('.pptx')) {
      return (
        icon: CupertinoIcons.play_rectangle_fill,
        color: const Color(0xFFE65100),
      );
    }
    if (n.endsWith('.zip') || n.endsWith('.rar') || n.endsWith('.7z')) {
      return (
        icon: CupertinoIcons.archivebox_fill,
        color: const Color(0xFF6D4C41),
      );
    }
    if (n.endsWith('.mp4') || n.endsWith('.mov') || n.endsWith('.avi')) {
      return (icon: CupertinoIcons.film_fill, color: const Color(0xFF6A1B9A));
    }
    if (n.endsWith('.mp3') || n.endsWith('.m4a') || n.endsWith('.wav')) {
      return (icon: CupertinoIcons.music_note, color: const Color(0xFFAD1457));
    }
    return (icon: CupertinoIcons.doc_fill, color: AppTheme.accent);
  }

  Future<void> _open() async {
    if (_downloading) return;
    setState(() => _downloading = true);
    try {
      final path = await widget.service.downloadAttachment(
        messageId: widget.messageId,
        attachmentId: widget.attachment.id,
        fileName: widget.attachment.name,
        directUrl: widget.attachment.url,
        storageId: widget.attachment.storageId,
      );
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done && mounted) {
        _showError('Datei konnte nicht geöffnet werden: ${result.message}');
      }
    } on WebUntisException catch (e) {
      if (mounted) _showError(e.message);
    } catch (e) {
      if (mounted) _showError('Fehler: ${simplifyErrorMessage(e)}');
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppTheme.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = _fileStyle;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: context.appBg,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: _downloading ? null : _open,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: [
                // Coloured file-type icon box (like Apple Mail / Files app)
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: style.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Icon(style.icon, size: 22, color: style.color),
                  ),
                ),
                const SizedBox(width: 12),

                // Name + size
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.attachment.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: context.appTextPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.attachment.size != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _formatSize(widget.attachment.size!),
                          style: TextStyle(
                            fontSize: 12,
                            color: context.appTextTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),

                // Right side: spinner or open icon
                _downloading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CupertinoActivityIndicator(radius: 10),
                      )
                    : Icon(
                        CupertinoIcons.arrow_up_right_circle_fill,
                        size: 22,
                        color: AppTheme.accent,
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

class _BodyWithLinks extends StatelessWidget {
  final String body;
  const _BodyWithLinks({required this.body});

  static final _urlRegex = RegExp(
    r'https?://[^\s)\]>"]+',
    caseSensitive: false,
  );

  @override
  Widget build(BuildContext context) {
    final matches = _urlRegex.allMatches(body).toList();

    if (matches.isEmpty) {
      return SelectableText(
        body,
        style: TextStyle(
          fontSize: 15,
          color: context.appTextPrimary,
          height: 1.5,
        ),
      );
    }

    final spans = <InlineSpan>[];
    int cursor = 0;

    for (final match in matches) {
      if (match.start > cursor) {
        spans.add(TextSpan(text: body.substring(cursor, match.start)));
      }
      final url = match.group(0)!;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTap: () async {
              final uri = Uri.tryParse(url);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: Text(
              url,
              style: TextStyle(
                fontSize: 15,
                color: AppTheme.accent,
                decoration: TextDecoration.underline,
                decorationColor: AppTheme.accent.withValues(alpha: 0.5),
                height: 1.5,
              ),
            ),
          ),
        ),
      );
      cursor = match.end;
    }

    if (cursor < body.length) {
      spans.add(TextSpan(text: body.substring(cursor)));
    }

    return SelectableText.rich(
      TextSpan(
        style: TextStyle(
          fontSize: 15,
          color: context.appTextPrimary,
          height: 1.5,
        ),
        children: spans,
      ),
    );
  }
}
