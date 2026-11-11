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

## Camera test script

`tools/camtest.py` queries the camera directly (Python 3, runs on a PC or in Termux). Join the camera's Wi-Fi first, then run `python tools/camtest.py`.
