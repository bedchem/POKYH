import 'dart:io' show Platform;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/webuntis_service.dart';
import '../theme/app_theme.dart';
import 'absences_screen.dart';
import 'grades_screen.dart';
import 'reminders_screen.dart';

bool get _isIOS => Platform.isIOS;

class HubScreen extends StatelessWidget {
  final WebUntisService service;
  const HubScreen({super.key, required this.service});

  void _open(BuildContext context, Widget screen) {
    Navigator.push(
      context,
      _isIOS
          ? CupertinoPageRoute(builder: (_) => screen)
          : MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 88),
                child: Text(
                  'Schule',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              _HubCard(
                icon: _isIOS
                    ? CupertinoIcons.chart_bar_fill
                    : Icons.bar_chart_rounded,
                title: 'Noten',
                subtitle: 'Alle Fächer & Bewertungen',
                color: AppTheme.accent,
                onTap: () => _open(context, GradesScreen(service: service)),
              ),
              const SizedBox(height: 14),
              _HubCard(
                icon: _isIOS ? CupertinoIcons.bell_fill : Icons.notifications,
                title: 'Erinnerungen',
                subtitle: 'Hausaufgaben & Klassen-Erinnerungen',
                color: AppTheme.tint,
                onTap: () => _open(context, RemindersScreen(service: service)),
              ),
              const SizedBox(height: 14),
              _HubCard(
                icon: _isIOS
                    ? CupertinoIcons.person_crop_circle_badge_xmark
                    : Icons.event_busy_rounded,
                title: 'Abwesenheiten',
                subtitle: 'Fehlstunden & Entschuldigungen',
                color: AppTheme.orange,
                onTap: () =>
                    _open(context, AbsencesScreen(service: service)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HubCard extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _HubCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  State<_HubCard> createState() => _HubCardState();
}

class _HubCardState extends State<_HubCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: widget.color.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(widget.icon, size: 24, color: widget.color),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                _isIOS ? CupertinoIcons.chevron_right : Icons.chevron_right,
                size: 18,
                color: AppTheme.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
