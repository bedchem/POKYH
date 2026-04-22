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
    if (mounted) {
      setState(() => _unread = widget.service.unreadMessageCount);
    }
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
          child: _BellIcon(unread: _unread),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _openProfile,
          child: _AvatarIcon(service: widget.service),
        ),
      ],
    );
  }
}

// ── Bell ──────────────────────────────────────────────────────────────────────

class _BellIcon extends StatelessWidget {
  final int unread;
  const _BellIcon({required this.unread});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 34,
      height: 34,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.appSurface,
              border:
                  Border.all(color: context.appBorder.withValues(alpha: 0.4)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                CupertinoIcons.bell_fill,
                size: 15,
                color: context.appTextSecondary,
              ),
            ),
          ),
          if (unread > 0)
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints:
                    const BoxConstraints(minWidth: 16, minHeight: 16),
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

// ── Avatar ────────────────────────────────────────────────────────────────────

class _AvatarIcon extends StatefulWidget {
  final WebUntisService service;
  const _AvatarIcon({required this.service});

  @override
  State<_AvatarIcon> createState() => _AvatarIconState();
}

class _AvatarIconState extends State<_AvatarIcon> {
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
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.appSurface,
        border: Border.all(color: context.appBorder.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes != null
          ? Image.memory(bytes, fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallback())
          : _fallback(),
    );
  }

  Widget _fallback() => Center(
        child: Icon(CupertinoIcons.person_fill,
            size: 16, color: context.appTextSecondary),
      );
}
