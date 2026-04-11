# ClassByte

A premium school cafeteria app built with Flutter. Displays the current meal plan with a calendar view, dietary filters, and push notifications. Designed with native iOS aesthetics using Cupertino widgets.

## Features

- **Weekly overview** with today's meals highlighted at the top
- **Calendar view** with daily meal details
- **Dietary filters** for vegetarian and vegan dishes
- **Pull-to-refresh** for live updates
- **Offline mode** with local caching
- **Daily reminder** via local notifications
- **Multilingual** support (German, English, Italian)
- **Native iOS design** using Cupertino components
- **Nutrition details** including calories, fat, and protein per dish
- **Dark mode** with system, light, and dark theme options

## Data Strategy

The app uses a multi-layer data strategy for maximum reliability:

1. **Cache (fast)** - Previously saved server data loaded from disk
2. **Server (6s timeout)** - Live data fetched from the configured API endpoint

If the server is unreachable, cached data is displayed with an offline notice. If no cache exists, an error message is shown.

```
Boot sequence:
[App Start] --> Load from cache --> Update UI
         |----> Fetch from server (max 6s) --> Save to cache --> Update UI
```

## JSON Format

The app expects JSON in the following format at the configured URL:

```json
{
  "menu": {
    "lastUpdated": "2026-04-10T12:00:00Z",
    "restaurant": "School Cafeteria",
    "dishes": [
      {
        "id": "m1",
        "name": "Penne with Tomato Sauce",
        "category": "Main Course",
        "date": "2026-04-10"
      }
    ]
  }
}
```

All fields except `name` are optional. Missing fields are filled with safe defaults. The app will never crash due to missing or malformed data in the JSON.

### Fields per Dish

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `id` | String | Hash of name | Unique identifier |
| `name` | String/Map | **Required** | Dish name (string or `{"de":"...","en":"..."}`) |
| `description` | String/Map | `""` | Description (string or localized map) |
| `imageUrl` | String | `""` | Image URL |
| `category` | String | `""` | Category |
| `tags` | List | Auto from category | Filter tags |
| `date` | String | Today | Date (YYYY-MM-DD) |
| `prepTime` | int | `0` | Preparation time in minutes |
| `calories` | int | `0` | Calories (kcal) |
| `protein` | double | `0` | Protein in grams |
| `fat` | double | `0` | Fat in grams |
| `price` | double | `0` | Price in EUR |
| `allergens` | List | `[]` | Allergens |
| `isVegetarian` | bool | Auto from category | Vegetarian flag |
| `isVegan` | bool | Auto from category | Vegan flag |
| `rating` | double | `0` | Rating (0-5) |

When nutrition data (calories, protein, fat) is not provided, the detail view displays "n/a" instead of hiding the field.

## Hosting the Menu

The JSON file can be hosted on any static file server. Example with GitHub Pages:

1. Create a repository with a `mensa.json` file
2. Enable GitHub Pages (Settings > Pages > Source: main branch)
3. Set the URL in `lib/config/app_config.dart`:
   ```dart
   static const String apiUrl = 'https://<username>.github.io/<repo>/mensa.json';
   ```
4. Update the JSON file and the app will show the new data

The app caches data locally so it works offline as well.

## Project Structure

```
lib/
  config/
    app_config.dart          # API URL configuration
  l10n/
    app_localizations.dart   # Translations (DE, EN, IT)
  models/
    dish.dart                # Data model with null-safe JSON parsing
  screens/
    home_screen.dart         # Weekly overview
    calendar_screen.dart     # Calendar view
    detail_screen.dart       # Dish detail with nutrition info
    settings_screen.dart     # Settings + AppSettings model
  services/
    dish_service.dart        # Data loading (server/cache)
    notification_service.dart # Local notifications
  widgets/
    dish_card.dart           # Dish card widget
    error_view.dart          # Error display
    loading_indicator.dart   # Loading spinner
    tag_chip.dart            # Filter chip
  main.dart                  # App entry point
```

## Getting Started

```bash
flutter pub get
flutter run
```

### iOS

```bash
flutter run -d <iPhone-Simulator-ID>
# or open in Xcode:
open ios/Runner.xcworkspace
```

## Configuration

Change the API URL in `lib/config/app_config.dart`:

```dart
class AppConfig {
  static const String apiUrl = 'https://mensa.plattnericus.dev/mensa.json';
}
```

## App Icon

`assets/app_icon.svg` is the single source of truth for the app icon.

For iOS, Apple still requires PNGs inside `ios/Runner/Assets.xcassets/AppIcon.appiconset/`. The project is configured to generate those sizes from the SVG via [flutter_launcher_icons](https://pub.dev/packages/flutter_launcher_icons) without adding a permanent script to the repo.

If the icon needs to be regenerated after changing the SVG:

```bash
flutter pub get
flutter pub run flutter_launcher_icons
```

## Requirements

- Flutter SDK >= 3.11.4
- iOS 13.0+
- Xcode 15+ (for iOS builds)
