<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.11+-02569B?style=for-the-badge&logo=flutter&logoColor=white" />
  <img src="https://img.shields.io/badge/Dart-3.11+-0175C2?style=for-the-badge&logo=dart&logoColor=white" />
  <img src="https://img.shields.io/badge/Firebase-12.9-FFCA28?style=for-the-badge&logo=firebase&logoColor=black" />
  <img src="https://img.shields.io/badge/Platform-iOS%20%7C%20Android-lightgrey?style=for-the-badge" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" />
</p>

<br>

<h1 align="center">
  <br>
  POCKYH
  <br>
</h1>

<h4 align="center">Die All-in-One Schul-App fuer die LBS Brixen &mdash; Stundenplan, Noten, Mensa & mehr.</h4>

<p align="center">
  <a href="#-features">Features</a> &bull;
  <a href="#-tech-stack">Tech Stack</a> &bull;
  <a href="#-architektur">Architektur</a> &bull;
  <a href="#-installation">Installation</a> &bull;
  <a href="#-projektstruktur">Projektstruktur</a> &bull;
  <a href="#-konfiguration">Konfiguration</a> &bull;
  <a href="#-api-referenz">API-Referenz</a> &bull;
  <a href="#-mitwirken">Mitwirken</a>
</p>

<br>

---

<br>

## Was ist POCKYH?

**POCKYH** verbindet den WebUntis-Stundenplan, das Notensystem und den Mensa-Speiseplan der LBS Brixen in einer einzigen, nativ wirkenden App. Kein Browser-Gefummel mehr, kein Wechsel zwischen drei verschiedenen Seiten &mdash; alles an einem Ort, blitzschnell und offline-faehig.

<br>

## &#x2728; Features

### &#x1F4C5; Stundenplan
- **Wochenansicht** mit Tagesauswahl (Mo&ndash;Fr)
- **Farbcodierung** nach Fach (Deutsch, Mathe, IT, Englisch, Sport, ...)
- **Pruefungs- und Entfall-Badges** auf einen Blick
- **Stundenraster** mit automatischer Pausenerkennung (10:20, 14:55)
- **"Jetzt" / "Als Naechstes"-Karte** auf dem Dashboard

### &#x1F4CA; Noten
- Alle Fachnoten mit **Durchschnittsberechnung**
- **Notenverteilung** (positiv/negativ) pro Fach
- Pruefungstyp und Datum fuer jede einzelne Note
- Schuljahr-basierte Abfrage (aktuell 2025/2026)

### &#x1F372; Mensa
- Taeglicher **Speiseplan mit Bildern**
- **Naehrwerte**, Allergene und Preise
- Vegetarisch/Vegan-Filter
- **Dreisprachig:** Deutsch, Italiano, English
- **Offline-Cache** &mdash; Speiseplan bleibt auch ohne Netz verfuegbar

### &#x1F464; Profil & Einstellungen
- WebUntis-**Profilbild** (automatisch gecacht, fehlerresistent)
- Kompakte Stundenplan-Ansicht
- Entfallene Stunden ein-/ausblenden
- Auto-Aktualisierung beim Oeffnen
- Sprachauswahl fuer Mensa-Menue

### &#x26A1; Allgemein
- **Session-Persistenz** &mdash; einmal einloggen, dauerhaft angemeldet
- **Pull-to-Refresh** ueberall
- **iOS-natives Dark-Mode Design** mit Cupertino-Widgets
- **Firebase-Integration** fuer zukuenftige Cloud-Features

<br>

## &#x1F527; Tech Stack

| Kategorie | Technologie |
|---|---|
| **Framework** | Flutter 3.11+ / Dart |
| **Backend-APIs** | WebUntis JSON-RPC + REST API |
| **Mensa-API** | `mensa.plattnericus.dev` |
| **Auth** | WebUntis Session-Cookies + Bearer Token |
| **Persistenz** | SharedPreferences (Session), Disk-Cache (Mensa) |
| **Cloud** | Firebase Core 12.9 |
| **HTTP** | `package:http` |
| **Design** | Cupertino-Widgets, SF Pro Text, iOS Dark Theme |
| **Sprachen** | Deutsch (primaer), Italienisch, Englisch |
| **Min. Plattform** | iOS 15.0+, Android SDK 21+ |

<br>

## &#x1F3D7; Architektur

```
                    +---------------------+
                    |      main.dart      |
                    |   Firebase Init     |
                    |   Session Restore   |
                    +---------+-----------+
                              |
               +--------------+--------------+
               |                             |
      +--------v--------+          +--------v---------+
      |   LoginScreen    |          |    HomeScreen     |
      |   (WebUntis)     |          |    (4 Tabs)       |
      +-----------------+          +--------+----------+
                                            |
                 +-----------+--------------+------------+
                 |           |              |            |
            Dashboard   Timetable       Grades       Mensa
                 |           |              |            |
                 +-----+-----+------+------+       +----+------+
                       |            |              |           |
                WebUntisService     |         DishService      |
                       |            |              |           |
                  WebUntis API      |         Mensa API    Disk Cache
                                    |
                             SharedPreferences
```

### Zwei-Service-Architektur

| Service | Verantwortung | API |
|---|---|---|
| **`WebUntisService`** | Auth, Stundenplan, Noten, Profilbild | `lbs-brixen.webuntis.com` |
| **`DishService`** | Speiseplan, Caching, Offline-Modus | `mensa.plattnericus.dev` |

### Daten-Strategie

```
Boot-Sequenz:
[App Start] --> Session aus SharedPreferences laden
          |--> Profilbild im Hintergrund vorladen
          |--> Stundenplan/Noten vom Server holen

Mensa-Sequenz:
[Mensa oeffnen] --> Cache aus RAM laden --> UI sofort anzeigen
              |--> Server-Fetch (max 6s) --> Cache aktualisieren --> UI updaten
              |--> Server-Fehler? --> Disk-Cache als Fallback
```

### State Management

Bewusst simpel: `StatefulWidget` + `setState`. Kein Provider, kein Riverpod, kein Bloc &mdash; die App-Komplexitaet rechtfertigt den Overhead nicht. Service-Instanzen werden per Constructor Injection durchgereicht.

<br>

## &#x1F680; Installation

### Voraussetzungen

- Flutter SDK >= 3.11.4
- Xcode 15+ (fuer iOS)
- Android Studio / Android SDK (fuer Android)
- CocoaPods (fuer iOS)

### Setup

```bash
# 1. Repository klonen
git clone https://github.com/your-username/POKYH.git
cd POKYH

# 2. Dependencies installieren
flutter pub get

# 3. iOS Pods installieren
cd ios && pod install && cd ..

# 4. App starten (Simulator)
flutter run

# 4b. Oder spezifisches Geraet
flutter run -d "iPhone 17"
```

### Firebase

Die Firebase-Konfiguration ist bereits eingerichtet:

| Plattform | Konfigurationsdatei |
|---|---|
| iOS | `ios/Runner/GoogleService-Info.plist` |
| Android | `android/app/google-services.json` |
| macOS | `macos/Runner/GoogleService-Info.plist` |
| Flutter | `lib/firebase_options.dart` |

Firebase-Projekt: **`pokyh-a92a5`**

### Build

```bash
# iOS Release
flutter build ios

# Android APK
flutter build apk

# Android App Bundle (Play Store)
flutter build appbundle
```

<br>

## &#x1F4C1; Projektstruktur

```
lib/
 |-- main.dart                        # App-Einstieg, Splash, Firebase Init
 |-- firebase_options.dart            # Firebase-Konfiguration (generiert)
 |
 |-- config/
 |   +-- app_config.dart              # API-URLs
 |
 |-- l10n/
 |   +-- app_localizations.dart       # Uebersetzungen (DE/EN/IT)
 |
 |-- models/
 |   +-- dish.dart                    # Gericht-Datenmodell (mehrsprachig)
 |
 |-- screens/
 |   |-- login_screen.dart            # WebUntis-Login
 |   |-- home_screen.dart             # Tab-Navigation + Dashboard
 |   |-- timetable_screen.dart        # Wochenansicht Stundenplan
 |   |-- grades_screen.dart           # Notenuebersicht
 |   |-- mensa_screen.dart            # Speiseplan
 |   |-- profile_screen.dart          # Profil & Einstellungen
 |   |-- detail_screen.dart           # Gericht-Detailansicht
 |   |-- calendar_screen.dart         # Monatskalender (Mensa)
 |   +-- settings_screen.dart         # Erweiterte Einstellungen
 |
 |-- services/
 |   |-- webuntis_service.dart        # WebUntis API-Client + Datenmodelle
 |   +-- dish_service.dart            # Mensa API + RAM/Disk-Caching
 |
 |-- theme/
 |   +-- app_theme.dart               # Dark Theme, Farben, Fach-Farben
 |
 +-- widgets/
     |-- dish_card.dart               # Gericht-Karte mit Hero-Animation
     |-- error_view.dart              # Fehleranzeige mit Retry
     |-- loading_indicator.dart       # Ladeindikator
     +-- tag_chip.dart                # Filter-Chips (Vegetarisch, Vegan)
```

<br>

## &#x2699; Konfiguration

### WebUntis

| Parameter | Wert |
|---|---|
| Schule | `lbs-brixen` |
| Base-URL | `https://lbs-brixen.webuntis.com/WebUntis` |
| Auth-Methode | JSON-RPC `authenticate` |
| Timeout | 15 Sekunden |
| Token | Bearer Token fuer REST-Endpunkte |

### Mensa-API

| Parameter | Wert |
|---|---|
| Endpoint | `https://mensa.plattnericus.dev/mensa.json` |
| Timeout | 6 Sekunden |
| Cache | Disk (JSON-Datei) + RAM |

Aendern in `lib/config/app_config.dart`:
```dart
class AppConfig {
  static const String apiUrl = 'https://mensa.plattnericus.dev/mensa.json';
}
```

### Design-System

#### Farben

| Farbe | Hex | Verwendung |
|---|---|---|
| Background | `#000000` | App-Hintergrund |
| Surface | `#1C1C1E` | Karten, Eingabefelder |
| Accent | `#0A84FF` | Buttons, Links, aktive Tabs |
| Success | `#30D158` | Positive Noten, freier Tag |
| Warning | `#FFD60A` | Pruefungs-Badge |
| Danger | `#FF453A` | Entfall-Badge, Logout, Fehler |

#### Fach-Farben

| Fach | Farbe | Hex |
|---|---|---|
| D (Deutsch) | Steel Blue | `#6B8CAE` |
| M (Mathe) | Sage Green | `#7BA seventeen` |
| IT | Terracotta | `#C47A5A` |
| Bew.Sport | Lavender | `#9B8EC4` |
| ENGL | Turquoise | `#5BA nineteen` |
| R (Religion) | Amber | `#C4A fourteen` |

<br>

## &#x1F310; API-Referenz

### WebUntis JSON-RPC

```http
POST /jsonrpc.do?school=lbs-brixen
Content-Type: application/json
Cookie: JSESSIONID=...; schoolname="_bGJzLWJyaXhlbg=="

{
  "jsonrpc": "2.0",
  "id": "1",
  "method": "authenticate",
  "params": {
    "user": "username",
    "password": "password",
    "client": "pockyh"
  }
}
```

### WebUntis REST-Endpunkte

| Endpunkt | Methode | Auth | Beschreibung |
|---|---|---|---|
| `/api/token/new` | GET | Cookie | Bearer Token holen |
| `/api/public/timetable/weekly/data` | GET | Cookie | Wochenstundenplan |
| `/api/classreg/grade/grading/list` | GET | Bearer + Cookie | Faecherliste mit Noten |
| `/api/classreg/grade/grading/lesson` | GET | Bearer + Cookie | Noten pro Fach |
| `/api/portrait/students/{id}` | GET | Cookie | Profilbild (JPEG) |

### Mensa JSON-Format

```json
{
  "menu": {
    "lastUpdated": "2026-04-10T12:00:00Z",
    "restaurant": "School Cafeteria",
    "dishes": [
      {
        "id": "m1",
        "name": { "de": "Penne mit Tomatensauce", "it": "Penne al pomodoro" },
        "category": "Hauptgericht",
        "date": "2026-04-10",
        "calories": 450,
        "price": 5.50,
        "isVegetarian": true
      }
    ]
  }
}
```

Alle Felder ausser `name` sind optional. Fehlende Felder werden mit sicheren Defaults gefuellt.

<br>

## &#x1F4E6; Datenmodelle

### TimetableEntry

```dart
TimetableEntry {
  int id, lessonId, date, startTime, endTime;
  String subjectName, subjectLong, teacherName, roomName;
  String cellState, lessonText;
  bool isCancelled, isExam;
}
```

### SubjectGrades

```dart
SubjectGrades {
  int lessonId;
  String subjectName, teacherName;
  List<GradeEntry> grades;
  double? average;              // Automatisch berechnet
  int positiveCount;            // Noten >= 6
  int negativeCount;            // Noten < 6
}
```

### GradeEntry

```dart
GradeEntry {
  int id, date, markValue;
  double markDisplayValue;
  String text, markName, examType;
}
```

### Dish

```dart
Dish {
  String id, imageUrl, category;
  Map<String, String> nameMap, descriptionMap;  // Mehrsprachig
  List<String> tags, allergens;
  int prepTime, calories;
  double protein, fat, price, rating;
  bool isVegetarian, isVegan;
  DateTime? date;
}
```

<br>

## &#x1F4F1; Bundle IDs

| Plattform | Bundle ID |
|---|---|
| iOS | `dev.plattnericus.project` |
| Android | `dev.plattnericus.project` |
| macOS | `dev.plattnericus.project` |

<br>

## &#x1F91D; Mitwirken

1. **Fork** das Repository
2. Erstelle einen Feature-Branch: `git checkout -b feature/mein-feature`
3. Committe deine Aenderungen: `git commit -m 'Add: Mein Feature'`
4. Push den Branch: `git push origin feature/mein-feature`
5. Oeffne einen **Pull Request**

### Commit-Konventionen

| Prefix | Bedeutung |
|---|---|
| `Add:` | Neues Feature |
| `Fix:` | Bugfix |
| `Update:` | Verbesserung bestehender Features |
| `Refactor:` | Code-Restrukturierung |
| `Docs:` | Dokumentation |

<br>

## Lizenz

Dieses Projekt ist Public unter der MIT Lizenz.

<br>

---

<p align="center">
  <sub>Gebaut mit Flutter & viel Koffein für die LBS Brixen &#x2615;</sub>
</p>
