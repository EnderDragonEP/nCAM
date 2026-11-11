# nCAM — build plan

Status: **approved 2026-11-11.** Steps 0–5 are built and confirmed on the phone and camera. Step 6 (live preview) is built and waiting for a test on the phone; step 7 (thumbnails, delete) is next.

## What the tests decided

| Finding | Consequence for the app |
|---|---|
| Listing and downloading work while recording, and recording keeps running. | Default behaviour: never touch recording. No mode switch, no stop. |
| 1.3–1.4 MB/s while recording; 3.1 MB/s in playback mode with recording stopped. A 10-minute clip is about 930 MB per camera: roughly 11 minutes versus 5. | Add an opt-in **fast download** that pauses recording. Off by default. |
| After playback mode, recording does **not** restart by itself; `2001 par=1` restarts it. | Fast download must restart recording itself, and verify it with `2016`. If the app is killed mid-download the camera would stay stopped, so the restart runs from the download service, and the app checks for a stopped camera on every connect. |
| Two parallel downloads are no faster than one. | One download at a time; a queue, not a pool. |
| Ranged requests work. | Resume and retry continue from the last byte. |
| The clip being recorded is listed and readable, and still growing. | Detect it (size changes between two listings), mark it "recording", and keep it out of batch downloads. |
| Thumbnail command returns `Status -3` while recording. | Thumbnails are made on the phone: fetch the first 1–2 MB of the clip with a ranged request, decode one frame, cache it. Use the camera's thumbnail only if it turns out to work when not recording. |
| `TIME` in the list is the last-write time; the start time is only in the file name `YYYY_MMDD_HHMMSS_nnnA.TS`. | Parse date and time from the name; fall back to `TIME`. |
| Dual camera: `…A.TS` front, `…B.TS` rear, in pairs. | Show a pair as one item with front/rear; download either or both. |
| No photo or event folder on the card. | The type filter is front / rear / (event, photo when such files exist), not three fixed tabs. Event detection stays unverified until an event clip exists. |
| Time sync works during recording; the new time shows from the next clip on. The camera was once found exactly one month behind for an unknown reason. | Sync on every connect and on demand. Flag clips whose name date disagrees with their write time, since those names are wrong. |
| Live view is MJPEG on port 8192; RTSP is closed. | Read the MJPEG stream on the bound connection and draw frames in Flutter. No libVLC. |
| The camera lists five settings; two have a real choice (audio, auto power off). | Settings screen: those two, plus Wi-Fi name/password, format card, factory reset, firmware and free space. Other ids from `3014` (loop length, G-sensor…) are shown read-only until a set is proven to work. |
| The web server answers "not found" with HTTP 200 and closes every connection. | Check content type and length, not the status code. No keep-alive assumptions. |

## Decisions

- **Android only, min SDK 29 (Android 10).** `WifiNetworkSpecifier` needs it; it gives the app its own camera network without making it the phone's default route. Cost: no Android 9 or older.
- **Flutter + Kotlin.** All camera networking is in Kotlin, because Dart's HTTP client cannot be bound to a specific Android `Network`.
- **Packages:** `flutter_riverpod` (state), `go_router` (navigation), `shared_preferences` + `flutter_secure_storage` (SSID, password), `media_kit` (playing `.TS` files and decoding thumbnail frames), `permission_handler`, `xml`. Kotlin: OkHttp, coroutines.

## Architecture

```
UI (Flutter)                     screens, widgets
State (Riverpod)                 connection, files, download queue, settings
CameraApi (Dart interface)       listFiles, recordingState, syncTime, setSetting, …
  ├─ NovatekCameraApi            builds commands, parses XML
  └─ FakeCameraApi               replays responses captured in the test logs
CameraTransport (Dart interface) get(path), stream(url), download jobs
  └─ platform channel
Kotlin                           WifiConnector  — scan, requestNetwork, hold Network
                                 CameraHttp     — OkHttp on network.socketFactory
                                 DownloadService — foreground service, queue,
                                                   Range resume, MediaStore
                                 MjpegReader    — frames to Dart
```

Tests run against `FakeCameraApi` and a fake transport, so parsing, pairing, queue logic and the UI need no camera.

## Android limits

- The first join shows a system approval dialog. Android 11+ remembers the approval for that network; Android 10 asks each time.
- Finding the camera needs the location permission (Android 10–12) or nearby-devices permission (13+), and Android throttles scans.
- The camera network exists only while the app holds it. Closing the app disconnects, except while the download service runs.
- Other apps keep mobile data. They cannot reach the camera, which is intended.
- If the phone is already joined to the camera through Android settings, the system treats it as the default Wi-Fi and other apps lose internet again. The app will detect this and say so.

## Build order

Each step ends with a short checklist to run on the phone and camera.

| # | Step | You test |
|---|---|---|
| 0 | Install Flutter, create the project, CI-style `flutter test` + `flutter build apk`. Fake camera and parsers, tested against the captured logs. | App installs and shows fake data. |
| 1 | **Connect in-app**: scan, pick camera, enter password once, remember it, reconnect with one tap. | Join without opening Android settings. |
| 2 | **Camera-only routing**: all requests bound to the camera network; status screen shows firmware, card, recording state. | Browse the web in another app on mobile data while connected. |
| 3 | **Time sync**: automatic on every connect, manual button, result checked, wrong-date clips flagged. | Next clip has the right name. |
| 4 | **Files and downloads**: list by date with front/rear pairs, in-progress clip marked, queue with progress, pause, resume, retry, batch; saved to the gallery. Recording untouched. | Download a batch while recording; kill Wi-Fi mid-file and resume. |
| 5 | **Fast download** (opt-in): pause recording, download, restart and verify recording; recovery on next connect. | Speed roughly doubles; recording is back afterwards, also after force-closing the app. |
| 6 | Live preview (MJPEG). | Smooth picture; front/rear switch if the camera supports it. |
| 7 | Thumbnails, filters, delete (single and batch). | — |
| 8 | Play downloaded clips; front/rear of the same moment. | — |
| 9 | Settings. | Audio toggle and auto power off take effect. |

## Still open

- Thumbnails and download speed with recording stopped but **without** playback mode (`2001 par=0` only). If that alone gives 3 MB/s, fast download gets simpler. Tested in step 5.
- Idle timeout (T9). Tested in step 2 by leaving the app connected.
- What set the camera clock one month back.
- Camera SSID and password, phone model and Android version.
