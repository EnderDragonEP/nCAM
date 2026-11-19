# nCAM

Android companion app for a Novatek-based Wi-Fi dash cam, replacing the vendor's "VF Cam" app.

- Joins the camera's Wi-Fi from inside the app and keeps the rest of the phone on its normal internet connection.
- Lists and downloads recordings without stopping recording.
- Sets the camera's clock on every connection.

## Docs

- [docs/camera-protocol.md](docs/camera-protocol.md) — the camera's HTTP protocol, with results measured on the real device.
- [docs/plan.md](docs/plan.md) — architecture and build order.

## Build

Needs Flutter (stable) and the Android SDK. Minimum Android version is 10.

```sh
flutter test
flutter build apk --release --target-platform android-arm64
```

### Where the APK ends up

The build writes the installable app to:

```text
build/app/outputs/flutter-apk/app-release.apk
```

- **Each build overwrites it.** The file name stays the same, so copy it somewhere else if you want to keep a particular version.
- **64-bit ARM only.** That covers current phones; drop `--target-platform android-arm64` to build for every CPU type (a larger file).
- **Signed with the debug key.** Android shows an "unknown app" warning when you install it, and a phone that has a differently signed copy must uninstall that first.

Install it by copying the file to the phone and opening it, or over USB with debugging enabled:

```sh
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

## Translations

All the text the app shows is in [lib/l10n/app_en.arb](lib/l10n/app_en.arb), in English. The code reads it through `context.l10n` (screens) or hands over a `Msg` (state code), so no sentence is written into the code itself. The app follows the phone's language and falls back to English.

To add a language, for example German:

1. Copy `lib/l10n/app_en.arb` to `lib/l10n/app_de.arb`, set `"@@locale": "de"`, and translate the values. Keep the `{placeholders}` and the `plural` structure. The `@` entries explain each text and do not need copying.
2. `dayPattern` is the format of the day headings (intl `DateFormat` letters). Change the order to suit the language, e.g. `EEE d. MMM y`.
3. For the notifications and the floating-window buttons, copy `android/app/src/main/res/values/strings.xml` to `res/values-de/strings.xml` and translate it.
4. Build. `flutter gen-l10n` runs as part of every build and regenerates `lib/l10n/app_localizations*.dart`. It lists anything still untranslated in `build/l10n_untranslated.json`.

Technical details inside messages, such as a camera status code or an Android error, stay in their original wording.

## Camera test script

`tools/camtest.py` queries the camera directly (Python 3, runs on a PC or in Termux). Join the camera's Wi-Fi first, then run `python tools/camtest.py`.
