
<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.11+-02569B?style=for-the-badge&logo=flutter&logoColor=white" />
  <img src="https://img.shields.io/badge/Dart-3.11+-0175C2?style=for-the-badge&logo=dart&logoColor=white" />
  <img src="https://img.shields.io/badge/Firebase-4.6+-FFCA28?style=for-the-badge&logo=firebase&logoColor=black" />
  <img src="https://img.shields.io/badge/Platform-iOS%20%7C%20Android-lightgrey?style=for-the-badge" />
  <img src="https://img.shields.io/badge/Version-1.1.5-blue?style=for-the-badge" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" />
</p>

<h1 align="center">POKYH</h1>

<p align="center">
  All-in-one school app for LBS Brixen — timetable, grades, mensa, reminders.
</p>

---

## Features

- **Timetable** — weekly view, exams, cancellations, now/next indicator
- **Grades** — averages, full subject overview
- **Mensa** — daily menu, filters, offline cache
- **Reminders** — local push notifications for upcoming events
- **Profile** — settings, auto-login, biometric auth
- Fast, clean, native UI (iOS & Android)

---

## Tech Stack

| Layer | Technology |
|---|---|
| UI | Flutter 3.11+ / Dart |
| Backend | Firebase (Auth, Firestore, Messaging) |
| School Data | WebUntis API (JSON-RPC + REST) |
| Local Storage | SharedPreferences + Disk Cache |
| Auth | firebase_auth + local_auth (biometrics) |
| Notifications | flutter_local_notifications + Firebase Messaging |

---

## Requirements

- Flutter SDK `^3.11.4`
- Dart SDK `^3.11.4`
- Firebase project with `google-services.json` (Android) and `GoogleService-Info.plist` (iOS)
- Valid WebUntis school account (LBS Brixen)

---

## Setup

```bash
git clone https://github.com/bedchem/POKYH.git
cd POKYH

flutter pub get
flutter run
```

> Make sure `google-services.json` is placed in `android/app/` and `GoogleService-Info.plist` in `ios/Runner/` before running.

---

## Build

### Android — Release APK

```bash
flutter clean
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

---

### iOS — IPA

```bash
flutter clean
flutter build ios --release

# Package into IPA
mkdir -p Payload
cp -R build/ios/iphoneos/Runner.app Payload/

zip -r ~/Downloads/Runner.ipa Payload

rm -rf Payload
```

Output: `Runner.ipa`

---

## Architecture

- StatefulWidgets + setState (no heavy state management)
- Services layer handles all external communication

**Services**

| Service | Responsibility |
|---|---|
| `WebUntisService` | Auth, timetable, grades (WebUntis JSON-RPC) |
| `DishService` | Mensa menu fetch + local caching |
| `NotificationService` | Scheduling & managing local reminders |
| `FirebaseService` | User auth, Firestore, push messaging |

---

## Project Structure

```
lib/
├── config/          # App configuration & constants
├── models/          # Data models (Dish, etc.)
├── screens/         # UI screens (timetable, grades, mensa, login, …)
├── services/        # Business logic & API layer
│   ├── webuntis_service.dart      # WebUntis JSON-RPC client
│   ├── dish_service.dart          # Mensa fetch + cache
│   ├── firebase_auth_service.dart # Firebase authentication
│   ├── reminder_service.dart      # Local reminder scheduling
│   ├── notification_service.dart  # Push notification handling
│   ├── update_service.dart        # In-app update checks
│   └── secure_credential_service.dart  # Keychain/Keystore storage
├── theme/           # App-wide theming
├── widgets/         # Reusable UI components
└── main.dart
```

---

## Security

- Credentials are stored in the device **Keychain / Keystore** via `flutter_secure_storage` — never in plain SharedPreferences
- Firebase API keys are scoped per platform and restricted in the Firebase Console
- **Never commit** `google-services.json`, `GoogleService-Info.plist`, or any `.env` file — these are excluded via `.gitignore`

---

## Environment & Configuration

All school-specific values (WebUntis server, school name) are set in `lib/config/app_config.dart`. No hardcoded secrets in source code.

| Config Key | Description |
|---|---|
| `webUntisServer` | WebUntis hostname for LBS Brixen |
| `schoolName` | School identifier used in API requests |

---

## Versioning

This project follows [Semantic Versioning](https://semver.org/).  
Current version: **1.1.5** — see `pubspec.yaml` for the full build number.

| Version | Highlights |
|---|---|
| 1.1.5 | Bug fixes, auth improvements |
| 1.1.0 | Reminders feature |
| 1.0.0 | Initial release — timetable, grades, mensa |

---

## Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/your-feature`
3. Commit your changes: `git commit -m "feat: add your feature"`
4. Push and open a Pull Request

Please keep PRs focused — one feature or fix per PR.

---

## License

MIT

```
MADE BY RYHOX AND NEXOR <3
```
