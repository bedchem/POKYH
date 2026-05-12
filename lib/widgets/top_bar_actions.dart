import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/webuntis_service.dart';
import '../theme/app_theme.dart';
import '../screens/messages_screen.dart';
import '../screens/profile_screen.dart';

class TopBarActions extends StatefulWidget {
  final WebUntisService service;
  final VoidCallback? onLogout;

  const TopBarActions({
    super.key,
    required this.service,
    this.onLogout,
  });

  @override
  State<TopBarActions> createState() => _TopBarActionsState();
}

class _TopBarActionsState extends State<TopBarActions> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _unread = widget.service.unreadMessageCount;
  }

  void _openMessages() async {
    await Navigator.push(
      context,
      Platform.isIOS
          ? CupertinoPageRoute(
              builder: (_) => MessagesScreen(service: widget.service))
          : MaterialPageRoute(
              builder: (_) => MessagesScreen(service: widget.service)),
    );
    if (mounted) setState(() => _unread = widget.service.unreadMessageCount);
  }

  void _openProfile() {
    Navigator.push(
      context,
      Platform.isIOS
          ? CupertinoPageRoute(
              builder: (_) => ProfileScreen(
                service: widget.service,
                onLogout: widget.onLogout ?? () {},
              ))
          : MaterialPageRoute(
              builder: (_) => ProfileScreen(
                service: widget.service,
                onLogout: widget.onLogout ?? () {},
              )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _openMessages,
          child: _MessageIcon(unread: _unread),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _openProfile,
          child: _ProfileAvatar(service: widget.service),
        ),
      ],
    );
  }
}

// ── Message Icon ──────────────────────────────────────────────────────────────

class _MessageIcon extends StatelessWidget {
  final int unread;
  const _MessageIcon({required this.unread});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.appSurface,
              border: Border.all(color: context.appBorder, width: 1.5),
            ),
            child: Center(
              child: Icon(
                CupertinoIcons.chat_bubble_fill,
                size: 16,
                color: AppTheme.accent,
              ),
            ),
          ),
          if (unread > 0)
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: BoxDecoration(
                  color: AppTheme.danger,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: context.appBg, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    unread > 99 ? '99+' : '$unread',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Profile Avatar ────────────────────────────────────────────────────────────

class _ProfileAvatar extends StatefulWidget {
  final WebUntisService service;
  const _ProfileAvatar({required this.service});

  @override
  State<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<_ProfileAvatar> {
  @override
  void initState() {
    super.initState();
    if (!widget.service.profileImageFetched) {
      widget.service.fetchProfileImage().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = widget.service.profileImageBytes;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.appSurface,
        border: Border.all(color: context.appBorder, width: 1.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes != null
          ? Image.memory(bytes, fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallback())
          : _fallback(),
    );
  }

  Widget _fallback() => Center(
        child: Icon(CupertinoIcons.person_fill, size: 16, color: AppTheme.accent),
      );
}
