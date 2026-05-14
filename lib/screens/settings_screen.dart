import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../l10n/app_localizations.dart';
import '../services/dish_service.dart';
import '../theme/app_theme.dart';
// notification_service removed - not used in current flow

class AppSettings {
  AppLanguage language;
  AppThemeMode themeMode;
  bool dailyReminder;
  bool newDishAlert;
  bool showCalories;
  bool showAllergens;
  bool showPrices;
  bool vegetarianOnly;
  bool veganOnly;

  AppSettings({
    this.language = AppLanguage.de,
    this.themeMode = AppThemeMode.system,
    this.dailyReminder = false,
    this.newDishAlert = true,
    this.showCalories = true,
    this.showAllergens = true,
    this.showPrices = true,
    this.vegetarianOnly = false,
    this.veganOnly = false,
  });
}

class SettingsScreen extends StatefulWidget {
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;

  const SettingsScreen({
    super.key,
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AppSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  void _update(void Function() change) {
    setState(change);
    widget.onSettingsChanged(_settings);
  }

  Future<void> _handleDailyReminderToggle(bool enabled) async {
    try {
      if (enabled) {
        // Notifications not available in current build
        _update(() => _settings.dailyReminder = false);
      } else {
        // cancelDailyReminder - notifications not available
      }
    } catch (_) {
      _update(() => _settings.dailyReminder = false);
    }
  }

  String _themeDisplayName(AppLocalizations l) {
    switch (_settings.themeMode) {
      case AppThemeMode.system:
        return l.get('theme_system');
      case AppThemeMode.light:
        return l.get('theme_light');
      case AppThemeMode.dark:
        return l.get('theme_dark');
    }
  }

  void _showThemePicker(BuildContext context) {
    final l = AppLocalizations.of(context);

    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(l.get('appearance')),
        actions: [
          _themeAction(
            ctx,
            l,
            AppThemeMode.system,
            CupertinoIcons.circle_lefthalf_fill,
            l.get('theme_system'),
          ),
          _themeAction(
            ctx,
            l,
            AppThemeMode.light,
            CupertinoIcons.sun_max_fill,
            l.get('theme_light'),
          ),
          _themeAction(
            ctx,
            l,
            AppThemeMode.dark,
            CupertinoIcons.moon_fill,
            l.get('theme_dark'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l.get('done')),
        ),
      ),
    );
  }

  CupertinoActionSheetAction _themeAction(
    BuildContext ctx,
    AppLocalizations l,
    AppThemeMode mode,
    IconData icon,
    String label,
  ) {
    final isSelected = _settings.themeMode == mode;
    return CupertinoActionSheetAction(
      onPressed: () {
        _update(() => _settings.themeMode = mode);
        Navigator.pop(ctx);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 20,
            color: isSelected
                ? CupertinoColors.activeBlue
                : CupertinoColors.secondaryLabel,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
              color: isSelected
                  ? CupertinoColors.activeBlue
                  : CupertinoColors.label.resolveFrom(ctx),
            ),
          ),
          if (isSelected) ...[
            const SizedBox(width: 8),
            const Icon(
              CupertinoIcons.checkmark_alt,
              size: 18,
              color: CupertinoColors.activeBlue,
            ),
          ],
        ],
      ),
    );
  }

  void _showLanguagePicker(BuildContext context) {
    final l = AppLocalizations.of(context);

    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(l.get('select_language')),
        actions: AppLanguage.values.map((lang) {
          final isSelected = _settings.language == lang;
          return CupertinoActionSheetAction(
            onPressed: () {
              _update(() => _settings.language = lang);
              Navigator.pop(ctx);
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(lang.flag, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 10),
                Text(
                  lang.displayName,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected
                        ? CupertinoColors.activeBlue
                        : CupertinoColors.label.resolveFrom(context),
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    CupertinoIcons.checkmark_alt,
                    size: 18,
                    color: CupertinoColors.activeBlue,
                  ),
                ],
              ],
            ),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: Text(l.get('done')),
        ),
      ),
    );
  }

  void _showCacheCleared(BuildContext context) async {
    await DishService().clearCache();
    // Also clear locally stored read message IDs.
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where((k) => k.startsWith('message_read_ids_')).toList()) {
      await prefs.remove(k);
    }

    if (!context.mounted) return;
    final l = AppLocalizations.of(context);
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(l.get('clear_cache')),
        content: Text(l.get('cache_cleared')),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final bgColor = CupertinoColors.systemBackground.resolveFrom(context);

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(l.get('settings')),
            border: null,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── General / Language + Theme ────────────────────
                  _sectionHeader(l.get('general'), context),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showLanguagePicker(context),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  CupertinoIcons.globe,
                                  size: 22,
                                  color: CupertinoColors.activeBlue,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    l.get('language'),
                                    style: TextStyle(
                                      fontSize: 17,
                                      color: CupertinoColors.label.resolveFrom(
                                        context,
                                      ),
                                    ),
                                  ),
                                ),
                                Text(
                                  '${_settings.language.flag} ${_settings.language.displayName}',
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: CupertinoColors.secondaryLabel
                                        .resolveFrom(context),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  CupertinoIcons.chevron_down,
                                  size: 14,
                                  color: CupertinoColors.systemGrey3
                                      .resolveFrom(context),
                                ),
                              ],
                            ),
                          ),
                        ),
                        _separator(context),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showThemePicker(context),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _settings.themeMode == AppThemeMode.dark
                                      ? CupertinoIcons.moon_fill
                                      : _settings.themeMode ==
                                            AppThemeMode.light
                                      ? CupertinoIcons.sun_max_fill
                                      : CupertinoIcons.circle_lefthalf_fill,
                                  size: 22,
                                  color: CupertinoColors.systemIndigo,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    l.get('appearance'),
                                    style: TextStyle(
                                      fontSize: 17,
                                      color: CupertinoColors.label.resolveFrom(
                                        context,
                                      ),
                                    ),
                                  ),
                                ),
                                Text(
                                  _themeDisplayName(l),
                                  style: TextStyle(
                                    fontSize: 15,
                                    color: CupertinoColors.secondaryLabel
                                        .resolveFrom(context),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  CupertinoIcons.chevron_down,
                                  size: 14,
                                  color: CupertinoColors.systemGrey3
                                      .resolveFrom(context),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Notifications ──────────────────────────────────
                  _sectionHeader(l.get('notifications'), context),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildSwitchRow(
                          context,
                          icon: CupertinoIcons.bell,
                          iconColor: CupertinoColors.systemOrange,
                          title: l.get('daily_reminder'),
                          subtitle: l.get('daily_reminder_desc'),
                          value: _settings.dailyReminder,
                          onChanged: (v) => _update(() {
                            _settings.dailyReminder = v;
                            _handleDailyReminderToggle(v);
                          }),
                        ),
                        _separator(context),
                        _buildSwitchRow(
                          context,
                          icon: CupertinoIcons.sparkles,
                          iconColor: CupertinoColors.systemPurple,
                          title: l.get('new_dish_alert'),
                          subtitle: l.get('new_dish_alert_desc'),
                          value: _settings.newDishAlert,
                          onChanged: (v) =>
                              _update(() => _settings.newDishAlert = v),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Display ────────────────────────────────────────
                  _sectionHeader(l.get('display'), context),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildSwitchRow(
                          context,
                          icon: CupertinoIcons.flame,
                          iconColor: CupertinoColors.systemRed,
                          title: l.get('show_calories'),
                          value: _settings.showCalories,
                          onChanged: (v) =>
                              _update(() => _settings.showCalories = v),
                        ),
                        _separator(context),
                        _buildSwitchRow(
                          context,
                          icon: CupertinoIcons.exclamationmark_triangle,
                          iconColor: CupertinoColors.systemYellow,
                          title: l.get('show_allergens'),
                          value: _settings.showAllergens,
                          onChanged: (v) =>
                              _update(() => _settings.showAllergens = v),
                        ),
                        _separator(context),
                        _buildSwitchRow(
                          context,
                          icon: CupertinoIcons.money_euro,
                          iconColor: CupertinoColors.systemGreen,
                          title: l.get('show_prices'),
                          value: _settings.showPrices,
                          onChanged: (v) =>
                              _update(() => _settings.showPrices = v),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Dietary ────────────────────────────────────────
                  _sectionHeader(l.get('dietary'), context),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildSwitchRow(
                          context,
                          icon: CupertinoIcons.leaf_arrow_circlepath,
                          iconColor: CupertinoColors.systemGreen,
                          title: l.get('vegetarian_only'),
                          value: _settings.vegetarianOnly,
                          onChanged: (v) => _update(() {
                            _settings.vegetarianOnly = v;
                            if (v) _settings.veganOnly = false;
                          }),
                        ),
                        _separator(context),
                        _buildSwitchRow(
                          context,
                          icon: CupertinoIcons.leaf_arrow_circlepath,
                          iconColor: AppTheme.tint,
                          title: l.get('vegan_only'),
                          value: _settings.veganOnly,
                          onChanged: (v) => _update(() {
                            _settings.veganOnly = v;
                            if (v) _settings.vegetarianOnly = false;
                          }),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── Data ───────────────────────────────────────────
                  _sectionHeader(l.get('data'), context),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _showCacheCleared(context),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              CupertinoIcons.trash,
                              size: 22,
                              color: CupertinoColors.systemRed,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l.get('clear_cache'),
                                    style: TextStyle(
                                      fontSize: 17,
                                      color: CupertinoColors.label.resolveFrom(
                                        context,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    l.get('clear_cache_desc'),
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: CupertinoColors.secondaryLabel
                                          .resolveFrom(context),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              CupertinoIcons.chevron_right,
                              size: 14,
                              color: CupertinoColors.systemGrey3.resolveFrom(
                                context,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // ── About ──────────────────────────────────────────
                  _sectionHeader(l.get('about'), context),
                  const SizedBox(height: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: bgColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _buildInfoRow(
                          context,
                          icon: CupertinoIcons.app,
                          iconColor: CupertinoColors.activeBlue,
                          label: l.get('app_name'),
                          value: 'ClassByte',
                        ),
                        _separator(context),
                        FutureBuilder<PackageInfo>(
                          future: PackageInfo.fromPlatform(),
                          builder: (context, snapshot) => _buildInfoRow(
                            context,
                            icon: CupertinoIcons.number,
                            iconColor: CupertinoColors.systemIndigo,
                            label: l.get('version'),
                            value: snapshot.data?.version ?? '…',
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // ── Footer ─────────────────────────────────────────
                  Center(
                    child: Column(
                      children: [
                        Icon(
                          CupertinoIcons.book,
                          size: 28,
                          color: CupertinoColors.systemGrey3.resolveFrom(
                            context,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'ClassByte',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: CupertinoColors.tertiaryLabel.resolveFrom(
                              context,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Made with Flutter',
                          style: TextStyle(
                            fontSize: 12,
                            color: CupertinoColors.quaternaryLabel.resolveFrom(
                              context,
                            ),
                          ),
                        ),
                      ],
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

  // ── Helpers ──────────────────────────────────────────────────────────

  Widget _sectionHeader(String title, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.5,
          color: CupertinoColors.secondaryLabel.resolveFrom(context),
        ),
      ),
    );
  }

  Widget _separator(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 52),
      child: Container(
        height: 0.5,
        color: CupertinoColors.separator.resolveFrom(context),
      ),
    );
  }

  Widget _buildSwitchRow(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 22, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 17,
                    color: CupertinoColors.label.resolveFrom(context),
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: CupertinoColors.secondaryLabel.resolveFrom(
                        context,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          CupertinoSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, size: 22, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 17,
                color: CupertinoColors.label.resolveFrom(context),
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }
}

