import 'package:flutter/cupertino.dart';
import 'config/app_config.dart';
import 'l10n/app_localizations.dart';
import 'models/dish.dart';
import 'services/dish_service.dart';
import 'screens/home_screen.dart';
import 'screens/calendar_screen.dart';
import 'screens/settings_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ClassByteApp());
}

class ClassByteApp extends StatefulWidget {
  const ClassByteApp({super.key});

  @override
  State<ClassByteApp> createState() => _ClassByteAppState();
}

class _ClassByteAppState extends State<ClassByteApp> {
  final DishService _service = DishService();
  final AppSettings _settings = AppSettings();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  List<Dish> _allDishes = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDishes();
  }

  Future<void> _loadDishes() async {
    final server = await _service.fetchFromServer();
    if (!mounted) return;
    if (server != null) {
      setState(() {
        _allDishes = server;
        _isLoading = false;
        _error = null;
      });
      return;
    }

    final cached = await _service.loadFromCache();
    if (!mounted) return;
    if (cached != null && cached.isNotEmpty) {
      setState(() {
        _allDishes = cached;
        _isLoading = false;
        _error = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _showOfflinePopup());
      return;
    }

    setState(() {
      _isLoading = false;
      _error = 'Keine Verbindung zum Server';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _showOfflinePopup());
  }

  void _showOfflinePopup() {
    final context = _navigatorKey.currentContext;
    if (context == null) return;

    final l = AppLocalizations.of(context);
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(l.get('offline_title')),
        content: Text(l.get('offline_message')),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            child: Text(l.get('done')),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
        ],
      ),
    );
  }

  Future<void> _refreshDishes() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final server = await _service.fetchFromServer();
    if (!mounted) return;

    if (server != null) {
      setState(() {
        _allDishes = server;
        _isLoading = false;
      });
    } else {
      setState(() {
        _isLoading = false;
        if (_allDishes.isEmpty) {
          _error = 'Keine Verbindung zum Server';
        }
      });
      _showOfflinePopup();
    }
  }

  List<Dish> get _filteredDishes {
    var dishes = _allDishes;
    if (_settings.veganOnly) {
      dishes = dishes.where((d) => d.isVegan).toList();
    } else if (_settings.vegetarianOnly) {
      dishes = dishes.where((d) => d.isVegetarian).toList();
    }
    return dishes;
  }

  void _onSettingsChanged(AppSettings settings) {
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final brightness = switch (_settings.themeMode) {
      AppThemeMode.light => Brightness.light,
      AppThemeMode.dark => Brightness.dark,
      AppThemeMode.system => null,
    };

    return LocalizationsProvider(
      localizations: AppLocalizations(_settings.language),
      child: CupertinoApp(
        navigatorKey: _navigatorKey,
        title: 'ClassByte',
        debugShowCheckedModeBanner: false,
        theme: CupertinoThemeData(
          primaryColor: CupertinoColors.activeBlue,
          brightness: brightness,
        ),
        home: _AppShell(
          dishes: _filteredDishes,
          isLoading: _isLoading,
          error: _error,
          onRefresh: _refreshDishes,
          settings: _settings,
          onSettingsChanged: _onSettingsChanged,
        ),
      ),
    );
  }
}

// ─── App Shell mit Tab Bar ───────────────────────────────────────────────────

class _AppShell extends StatefulWidget {
  final List<Dish> dishes;
  final bool isLoading;
  final String? error;
  final VoidCallback onRefresh;
  final AppSettings settings;
  final ValueChanged<AppSettings> onSettingsChanged;

  const _AppShell({
    required this.dishes,
    required this.isLoading,
    this.error,
    required this.onRefresh,
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  final CupertinoTabController _tabController = CupertinoTabController();

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return CupertinoTabScaffold(
      controller: _tabController,
      tabBar: CupertinoTabBar(
        items: [
          BottomNavigationBarItem(
            icon: const Icon(CupertinoIcons.square_list),
            activeIcon: const Icon(CupertinoIcons.square_list_fill),
            label: l.get('menu'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(CupertinoIcons.calendar),
            activeIcon: const Icon(CupertinoIcons.calendar),
            label: l.get('calendar'),
          ),
          BottomNavigationBarItem(
            icon: const Icon(CupertinoIcons.gear),
            activeIcon: const Icon(CupertinoIcons.gear_solid),
            label: l.get('settings'),
          ),
        ],
      ),
      tabBuilder: (context, index) {
        switch (index) {
          case 0:
            return HomeScreen(
              dishes: widget.dishes,
              isLoading: widget.isLoading,
              error: widget.error,
              onRefresh: widget.onRefresh,
              settings: widget.settings,
            );
          case 1:
            return CalendarScreen(
              dishes: widget.dishes,
              settings: widget.settings,
            );
          case 2:
            return SettingsScreen(
              settings: widget.settings,
              onSettingsChanged: widget.onSettingsChanged,
            );
          default:
            return HomeScreen(
              dishes: widget.dishes,
              isLoading: widget.isLoading,
              error: widget.error,
              onRefresh: widget.onRefresh,
              settings: widget.settings,
            );
        }
      },
    );
  }
}
