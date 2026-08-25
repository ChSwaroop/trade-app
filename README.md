# TradeDirect

A simulated trading app for 10 NSE stocks with a mock live market feed, built with Flutter.

## Prerequisites

- [Flutter SDK](https://docs.flutter.dev/get-started/install) (Dart SDK `^3.12.2`)
- A connected device, emulator/simulator, or a desktop/web target enabled

Check your setup with:

```bash
flutter doctor
```

## Getting Started

Install dependencies:

```bash
flutter pub get
```

Run the app (pick a connected device/emulator, or omit `-d` to be prompted):

```bash
flutter run
```

Run on a specific platform:

```bash
flutter run -d android   # Android emulator/device
flutter run -d ios       # iOS simulator/device
flutter run -d chrome    # Web
flutter run -d macos     # macOS desktop
flutter run -d windows   # Windows desktop
flutter run -d linux     # Linux desktop
```

## Building

```bash
flutter build apk        # Android APK
flutter build ios        # iOS build (requires macOS + Xcode)
flutter build web        # Web build
flutter build macos      # macOS build
flutter build windows    # Windows build
flutter build linux      # Linux build
```

## Running Tests

```bash
flutter test
```
