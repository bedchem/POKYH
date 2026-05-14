import 'dart:io';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppIconOption {
  final String displayName;
  final String? iconName; // null = Standardicon
  final String previewAsset;

  const AppIconOption({
    required this.displayName,
    required this.previewAsset,
    this.iconName,
  });
}

class AppIconService {
  static const _channel = MethodChannel('pokyh/app_icon');
  static const _prefKey = 'selected_app_icon';

  // ── Verfügbare Icons ──────────────────────────────────────────────────────
  // Neues Icon hinzufügen:
  //   1. PNG in assets/icons/ ablegen
  //   2. Appiconset in ios/Runner/Assets.xcassets/ erstellen (icon@2x + @3x, Contents.json)
  //   3. Eintrag in ios/Runner/Info.plist unter CFBundleAlternateIcons hinzufügen
  //   4. Hier eine neue AppIconOption eintragen
  static const List<AppIconOption> icons = [
    AppIconOption(
      displayName: 'Standard',
      iconName: null,
      previewAsset: 'assets/icons/POKYH_icon.png',
    ),
    AppIconOption(
      displayName: 'Klassisch',
      iconName: 'AppIconKlassisch',
      previewAsset: 'assets/icons/image4.png',
    ),
    AppIconOption(
      displayName: 'Heinrich',
      iconName: 'AppIconNexor',
      previewAsset: 'assets/icons/image2.png',
    ),
    AppIconOption(
      displayName: 'Siggidy',
      iconName: 'AppIconNexor2',
      previewAsset: 'assets/icons/image3.png',
    ),
    AppIconOption(
      displayName: 'Special',
      iconName: 'AppIconSpez',
      previewAsset: 'assets/icons/image5.png',
    ),
  ];

  static bool get isSupported => Platform.isIOS || Platform.isAndroid;

  static Future<String?> getCurrentIconName() async {
    if (!isSupported) return null;
    try {
      final name = await _channel.invokeMethod<String?>('getIcon');
      return name;
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_prefKey);
    }
  }

  static AppIconOption currentOption(String? iconName) {
    return icons.firstWhere(
      (o) => o.iconName == iconName,
      orElse: () => icons.first,
    );
  }

  static Future<bool> setIcon(AppIconOption option) async {
    if (!isSupported) return false;
    try {
      await _channel.invokeMethod('setIcon', {'iconName': option.iconName});
      final prefs = await SharedPreferences.getInstance();
      if (option.iconName == null) {
        await prefs.remove(_prefKey);
      } else {
        await prefs.setString(_prefKey, option.iconName!);
      }
      return true;
    } catch (_) {
      return false;
    }
  }
}
