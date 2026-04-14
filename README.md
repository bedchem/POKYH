
<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.11+-02569B?style=for-the-badge&logo=flutter&logoColor=white" />
  <img src="https://img.shields.io/badge/Dart-3.11+-0175C2?style=for-the-badge&logo=dart&logoColor=white" />
  <img src="https://img.shields.io/badge/Firebase-12.9-FFCA28?style=for-the-badge&logo=firebase&logoColor=black" />
  <img src="https://img.shields.io/badge/Platform-iOS%20%7C%20Android-lightgrey?style=for-the-badge" />
  <img src="https://img.shields.io/badge/License-MIT-green?style=for-the-badge" />
</p>

<h1 align="center">POKYH</h1>

<p align="center">
  All-in-one school app for LBS Brixen — timetable, grades, mensa.
</p>

---

## Features

- Timetable (weekly view, exams, cancellations, now/next)
- Grades (averages, full subject overview)
- Mensa (daily menu, filters, offline cache)
- Profile (settings, auto-login)
- Fast, clean, native UI

---

## Tech Stack

- Flutter 3.11+
- Dart
- Firebase
- WebUntis API (JSON-RPC + REST)
- SharedPreferences + Disk Cache

---

## Setup

```bash
git clone https://github.com/bedchem/POKYH.git
cd POKYH

flutter pub get
flutter run
````

---

## Build

### Android (Release APK)

```bash
cd ~/Downloads/POKYH

flutter clean

flutter build apk --release

cd ~/Downloads

rm -f POKYH.apk

cp ~/Downloads/POKYH/build/app/outputs/flutter-apk/app-release.apk POKYH.apk

echo "Fertig: ~/Downloads/POKYH.apk"
```

---

### iOS (IPA)

```bash
cd ~/Downloads/POKYH

flutter clean

flutter build ios --release



cd ~/Downloads

rm -rf Payload Runner.ipa

mkdir -p Payload

cp -R ~/Downloads/POKYH/build/ios/iphoneos/Runner.app Payload/

zip -r Runner.ipa Payload

rm -rf Payload Ergebnis
```

Final file:

```
~/Downloads/Runner.ipa
```

---

## Architecture

* StatefulWidgets + setState
* No heavy state management

**Services**

* WebUntisService → auth, timetable, grades
* DishService → mensa + caching

---

## License

MIT

```
MADE BY RYHOX AND NEXOR <3 
```
