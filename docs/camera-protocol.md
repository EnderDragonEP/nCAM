# Camera protocol — VF Cam 1.1.12 (`com.lzx.camera`)

Source: `base.apk` from `.apk/VF Cam_1.1.12.apks`, decompiled with jadx 1.5.6. The app is native Java/Kotlin (Retrofit + OkHttp, libVLC, ExoPlayer). Class names below are the obfuscated ones, with the original source file name jadx recovered in brackets.

**How to read the status column**

- **Code** — the request is built this way in the decompiled app. The camera's behaviour is still unverified until you run it.
- **Unclear** — the code does not settle it; there is a test in [section 10](#10-tests-to-run).

No response in this document was captured from a real camera. The "response" columns list only the XML tags the app's parsers read, so the real response may contain more.

---

## 0. Verified on the real camera (2026-11-11)

Measured with `tools/camtest.py` from the phone, **while the camera was recording**. Where this section disagrees with the code-derived sections below, this section wins.

| Item | Result |
|---|---|
| Firmware (3012) | `DVR52AFHW3_YL_V3.19_TS` |
| Identity (8005) | `*LZXA221_935H_V1.05-WZX_456#_MODIFY*May 28 2021, 14:47:57` — matches the app's gate |
| HTTP server | `hfs/1.00.000`, `Connection: close` on every response, `Accept-Ranges: bytes` |
| Files | Dual camera. Everything is in `/Novatek/Movie/`, named `YYYY_MMDD_HHMMSS_nnnA.TS` (front) and `…_nnnB.TS` (rear), in pairs. No photo folder and no event/locked folder existed on the card. |
| File list (3015) | Works during recording, about 0.4 s for 48 files. Each entry is `<ALLFile><File>…</File></ALLFile>` with `NAME`, `FPATH`, `SIZE`, `TIMECODE`, `TIME`, `ATTR` (32 on every file). `TIME` is the **last-write time**, not the start: the start time is only in the file name. The clip being recorded is listed; its `SIZE` and `TIME` change between calls, which is how to detect it. |
| HTML index | `http://192.168.1.254/Novatek/Movie/` lists the same files with rounded sizes; each row has a `?del=1` delete link. `/` shows `LOG`, `CardStatus.txt`, `NOVATEK`. Unknown paths return HTTP 200 with a "Page Not found" body, so status codes cannot be trusted. |
| Download during recording | **Works; recording kept running** (three runs). Speed 1.32–1.38 MB/s. The clip still being written can be read too. |
| Parallel downloads | Two at once gave 1.45 MB/s combined — no gain. The link is the limit; download one file at a time. |
| Range / resume | **Supported**: `206` with correct `Content-Range` for both `bytes=a-b` and `bytes=a-`. |
| Thumbnail (4001) | **Fails during recording**: `<Status>-3</Status>` instead of a JPEG. Not yet tested with recording stopped. |
| Time (3005 / 3006) | Both return `Status 0` during recording; recording keeps running. **The new time only shows in the name of the next clip**: the clip started after the sync was named `2026_1111_200627…`, correct. |
| Clock anomaly | Before the first sync the camera clock was **exactly one month behind** (clip named `2026_1011_195621…`, `TIME` 2026/10/11) with the right time of day, although clips up to 19:23 the same day were dated correctly. What set it wrong between 19:23 and 19:56 is unknown. Our sync fixed it. |
| Live view (2019) | Both links are `http://192.168.1.254:8192` (MJPEG). Port 554 (RTSP) is closed. |
| Ports | Open: 80, 3333, 8192. Closed: 21, 23, 554, 8080. Socket 3333 sent nothing in 8 s. |
| Settings (3031) | Only five: `PHOTO_SIZE` (one option), `MOVIE_SIZE` (one option), `EV` (one option), `MOVIE_AUDIO` (OFF/ON), `AUTO_POWER_OFF` (ON/3MIN/5MIN/10MIN). Option `Index` values are contiguous from 0. |
| Current values (3014) | Also reports ids that 3031 does not list: 2003=3, 2004=1, 2006=1, 2008=1, 2011=1, 2012=1, 2020=50, 2022=8000, 3008=7, 3009=0, 3028=2, 3033=0 and others. Whether those can be changed is untested. 2003=3 is consistent with the observed 10-minute clips (about 930 MB per clip, per camera). |
| Card / space / battery | 3024 = 33 (card OK), 3017 = 121 GB free, 3019 = 5 |

| Playback mode (T5) | `3001 par=2` **stops recording** (2016 → 0). Download speed rose from 1.38 to **3.12 MB/s**. `3001 par=1` took 5 s to answer and recording **did not restart by itself** (still 0 after 15 s); `2001 par=1` restarted it. |

### Seen in daily use (2026-11-12 to 11-13, from the app's diagnostic log)

| Item | Result |
|---|---|
| File list (3015) refused | Answers `<Function><Cmd>3015</Cmd><Status>-3</Status></Function>` instead of a list. Seen on a freshly formatted card while recording, and on 11-12 while recording with files on the card. From 11-16 to 11-18 **every** listing during recording was refused; each time recording stopped (`2001 par=0`, 2016 → 0) the list came back within seconds (e.g. 11-18 18:32:28 stop, 18:32:33 list). On 11-11 the list worked during recording, so why it started is unknown. The app now falls back to the HTML folder page (`/Novatek/Movie/`, sizes rounded to 0.01 MB), and if that fails too offers to pause recording for a few seconds to read the list. **Confirmed 11-19:** the folder page is served while 3015 is refused, so the list shows during recording. |
| Card status (3024) | `1` on 11-13, `33` on 11-11. Meaning of the values unknown. |
| Link loss during live view | Android reported the camera link lost twice in 14 minutes with live view open. Android did not rejoin by itself for over a minute; Disconnect + Connect fixed it. |
| View index (3028) | `0` = front, `1` = rear, `2` = both side by side. |
| Clip rollover | 2016 resets every 10 minutes (loop length 2003 = 3). |
| Recording + download + live view | All three at once work (11-19): the camera keeps recording, files download, and live view plays, though the live picture stutters a little while a download runs (they share the ~1.3 MB/s link). |

Not yet run: T9 (idle timeout), thumbnails with recording stopped, and whether stopping recording alone (`2001 par=0`, without playback mode) gives the same speed-up.

---

## 1. Summary

- The app only ever talks to a **Novatek** camera at `192.168.1.254`. Ambarella code (`192.168.42.1`, port 7878) is in the APK but is never instantiated: `y4.h.c()` creates `c5.d` [LYCamera] only when the Wi-Fi gateway is `192.168.1.254`, and nothing else.
- Everything is plain HTTP GET on port 80: `http://192.168.1.254/?custom=1&cmd=<id>[&par=<n> | &str=<text>]`.
- Responses are XML. The app reads them with substring searches, not a real XML parser, for most commands.
- **The app does not send a heartbeat** (cmd 3016 does not appear anywhere). The only periodic request is the battery poll (3019) every 15 s while the live screen is open.
- **Time sync already exists**: the app sends 3005 and 3006 once at the end of every connection handshake. If your clock still drifts, either those calls fail silently (the app ignores the result) or the camera loses time between connections. See test T6.
- **Download is a plain GET of the file URL**, the same thing your browser does. The app has no Range/resume support and downloads one file at a time.
- **Recording blocks the gallery in the UI, not provably in the camera.** While recording, the app disables the gallery and settings buttons. When the gallery opens it sends `3001 par=2` (playback mode) before listing. Nothing in the code shows that listing or downloading fails during recording — that is test T3/T4.

---

## 2. Transport

| Item | Value | Evidence |
|---|---|---|
| Base URL | `http://192.168.1.254/` | `c5.e` [LYCameraProtocol] constructor |
| Command form | `GET /?custom=1&cmd=<int>` | `LYCameraApi.sendCmd` |
| With number | `…&cmd=<int>&par=<value>` | `LYCameraApi.sendCmdWithPar` |
| With text | `…&cmd=<int>&str=<text>` (URL-encoded by Retrofit) | `LYCameraApi.sendCmdWithStr` |
| Timeouts | connect 5 s, read 10 s | `c5.e` |
| Success test | `<Status>` equals `0` | `y4.i.g()`, `c5.b.k()` |
| Notification socket | TCP `192.168.1.254:3333`, camera pushes XML | `c5.d.g0()`, `y4.l` |
| Live view | `rtsp://192.168.1.254:554/xxx.mp4` and `http://192.168.1.254:8192` (defaults; replaced by cmd 2019) | `c5.e` static fields |
| Cleartext | allowed for all hosts | `res/xml/network_security_config.xml` |

Response fields the app reads (`c5.b` [LYCamResponse]):

```xml
<Function>
  <Cmd>3019</Cmd>       <!-- echoed command id -->
  <Status>0</Status>    <!-- 0 = OK; missing = treated as -1 (failure) -->
  <Value>87</Value>     <!-- numeric result, when there is one -->
  <String>…</String>    <!-- text result, when there is one -->
</Function>
```

The wrapper element name (`<Function>`) is the usual Novatek one and is **not** checked by the app.

---

## 3. Camera detection and network handling in the official app

| What | How | Evidence |
|---|---|---|
| Joining Wi-Fi | Not done by the app. It opens Android's Wi-Fi picker (`android.net.wifi.PICK_WIFI_NETWORK`). | `m5.b.c()`, `CamConnectionActivity.j0()` |
| Detecting the camera | Reads the DHCP server address (falls back to gateway) of the current Wi-Fi; `192.168.1.254` = this camera. | `y4.j.H()`, `h5.f.e()` |
| Routing | On app start: `requestNetwork(TRANSPORT_WIFI)` then `bindProcessToNetwork(network)`. This binds the whole app process to Wi-Fi. It does nothing for other apps, which is why the phone as a whole loses internet. | `m5.b.a()`, called from `MainActivity.onCreate` |

Permissions declared: `INTERNET`, `ACCESS/CHANGE_WIFI_STATE`, `ACCESS/CHANGE_NETWORK_STATE`, `ACCESS_FINE/COARSE_LOCATION`, `READ_MEDIA_*`, `WAKE_LOCK`. Min SDK 21.

---

## 4. Connection handshake

Run on a background thread when the user taps "Connect" (`c5.d.b1()` [LYCamera.syncConnection]). Order matters; the app aborts with "cannot match" where noted.

| # | Request | What the app does with it | Abort if |
|---|---|---|---|
| 1 | `cmd=3031&str=all` | Collects every `<Name>` tag. | fewer than 3 names, or the first three are not `PHOTO_SIZE`, `MOVIE_SIZE`, `EV` |
| 2 | `cmd=8005` | Reads `<String>`. | it does not start with `*LZXA221_935H_V1.05-WZX_456#_MODIFY*` |
| 3 | `cmd=3012` | Firmware version from `<String>`. Also reads `<ProNo>` (`6700` sets a flag passed to the player) and `<ENCAP>` (`1` hides the photo/video mode tabs). | no response |
| 4 | `cmd=2019` | Reads `<MovieLiveViewLink>` and `<PhotoLiveViewLink>`; these replace the default live-view URLs. If both are equal and non-empty the camera is treated as dual-view (see 3028). | — |
| 5 | `cmd=3001&par=1` | Switch to movie mode. On success, starts live view (step in section 7). | — |
| 6 | `cmd=3024` | Card status from `<Value>`: `0` = no card; `1`, `17`, `33` = card usable. | — |
| 7 | `cmd=2016` | Only if the card is usable. `<Value>` > 0 means **recording is in progress** (value is elapsed seconds). | — |
| 8 | `cmd=3014` | All current setting values: a sequence of `<Cmd>id</Cmd><Status>value</Status>` pairs. | — |
| 9 | `cmd=3031&str=all` (again) | Option lists per setting (section 8). | — |
| 10 | `cmd=3005&str=yyyy-MM-dd`, then `cmd=3006&str=HH:mm:ss` | Sets date and time from the phone clock. Fire-and-forget; result ignored. | — |
| 11 | `cmd=3017` | Free space in bytes from `<Value>`. | — |

Step 2 is a vendor lock: the app refuses any camera whose 8005 string is different. It tells us the firmware family this app was built for (**LZXA221 / 935H, V1.05**). Our app does not need the gate, but the string is a useful identity check. See T1.

---

## 5. Command reference

Evidence for all rows is `c5/d.java` [LYCamera] unless stated.

### Status and info

| Cmd | Parameter | Reads | Purpose | Status |
|---|---|---|---|---|
| 3012 | — | `<String>`, `<ProNo>`, `<ENCAP>` | Firmware version | Code |
| 8005 | — | `<String>` | Vendor identity string | Code |
| 3014 | — | `<Cmd>`/`<Status>` pairs | Current value of every setting | Code |
| 3031 | `str=all` | `<Name>`, `<Cmd>`, `<Id>`, grouped by `<Item>` | Supported settings and their options | Code |
| 3019 | — | `<Value>` | Battery level. Polled every 15 s on the live screen. | Code |
| 3024 | — | `<Value>` | SD card status | Code |
| 3017 | — | `<Value>` (bytes) | Free space | Code |
| 2016 | — | `<Value>` (seconds) | Recording elapsed time; > 0 = recording | Code |
| 3016 | — | — | Heartbeat. **Not used by this app.** Whether the camera needs it is unknown. | Unclear (T9) |

### Mode, recording, capture

| Cmd | Parameter | Purpose | Status |
|---|---|---|---|
| 3001 | `par=0` photo, `par=1` movie, `par=2` playback | Switch camera mode. The gallery sends `par=2` before listing files. Returning to the live screen sends `par=1` (or `0`). | Code |
| 2001 | `par=1` start, `par=0` stop | Start/stop recording (movie mode) | Code |
| 1001 | `par=0` | Take a photo (photo mode) | Code |
| 3028 | `par=<view index>` | Switch displayed lens on dual-view cameras | Code; values unclear |
| 8006 | none, or `par=4` | Vendor command. Sent with no parameter when the settings screen closes; `par=4` only from an unused "SJ8Pro" screen. Purpose not determinable from code. | Unclear — we will not send it |

### Time

| Cmd | Parameter | Purpose | Status |
|---|---|---|---|
| 3005 | `str=yyyy-MM-dd` | Set date | Code |
| 3006 | `str=HH:mm:ss` | Set time | Code |

There is **no command in the app that reads the camera's clock back.** To verify a sync we have to look at the timestamp of a newly recorded file or the on-video date stamp. See T6.

### Storage and system

| Cmd | Parameter | Purpose | Status |
|---|---|---|---|
| 3010 | `par=1` | Format SD card | Code |
| 3011 | `par=1` | Restore factory settings. The camera then closes the session. | Code |
| 3003 | `str=<ssid>` | Set camera Wi-Fi name | Code |
| 3004 | `str=<password>` | Set camera Wi-Fi password | Code |
| 3021 | — | Sent right after 3003 + 3004; applies the new Wi-Fi settings (presumably restarts Wi-Fi) | Code; effect unclear |

---

## 6. Files

### List — `cmd=3015`

One request returns **all** files; the app splits them into tabs itself (`c5.d.R0()`).

Tags read per `<File>`:

```xml
<File>
  <NAME>20260101_120000A.MP4</NAME>
  <FPATH>A:\CARDV\MOVIE\20260101_120000A.MP4</FPATH>
  <SIZE>123456789</SIZE>          <!-- bytes -->
  <TIME>2026/01/01 12:00:00</TIME>
</File>
```

The file name and folder above are **placeholders**; real folder names are not in the app. T2 shows them.

| Rule | Detail |
|---|---|
| Download URL | `http://192.168.1.254` + FPATH with `A:` removed and `\` → `/` |
| Video vs photo | extension `.mp4`, `.mov`, `.ts` = video; anything else = photo |
| Event/locked video | a video whose URL contains `ro` (case-insensitive). Meant to match a read-only folder such as `/RO/`, but it is a crude substring match. |
| Date grouping | TIME with `/` → `-`, text before the space is the date |
| Sort | by TIME string, newest first |

### Thumbnail

`GET <file URL>?custom=1&cmd=4001` — returns an image (loaded straight into Glide). Used for videos and photos alike (`MediaModel.u()`). Status: Code.

### Download

`GET <file URL>` with `HttpURLConnection` (`d5/c.java`): 30 s connect timeout, 2 MB buffer, single-threaded executor (one file at a time), no `Range` header, no retry. A file is written as `<name>.mp4` temp and renamed on success; a short file is deleted. Nothing in this code explains the slow speed you see — the request is the same one a browser makes. Likely suspects are the camera being in playback mode (3001 par=2) or the live-view session still held open; T5 separates them.

### Play from the camera

The app hands the file URL to ExoPlayer (or libVLC for files over 2 GB). So the camera's HTTP server is expected to handle streaming reads; whether it honours `Range` is T4.

### Delete — `cmd=4003`

`cmd=4003&str=A:\<path with backslashes>` (the reverse of the URL mapping). Batch delete is one request per file with a 50 ms pause. Status: Code.

### Directory index

`LYCameraApi` declares `GET DCIM/{type}/` but nothing calls it for this camera. The browsable index you use in the phone browser is therefore **not** something the app relies on; its path and HTML format must come from T2.

---

## 7. Live view

| Step | Request | Evidence |
|---|---|---|
| Get URLs | `cmd=2019` → `<MovieLiveViewLink>`, `<PhotoLiveViewLink>` | `c5.d.W0()` |
| Start stream | `cmd=2015&par=1`, then open the player about 1.5 s later | `c5.d.Z0()` |
| Player | libVLC, options `:network-caching=600`, `:file-caching=600`, `:codec=all`, audio off | `SStreamPlayer` |

URL choice: movie mode uses the movie link (default `rtsp://192.168.1.254:554/xxx.mp4`); photo mode uses the photo link (default `http://192.168.1.254:8192`, MJPEG). If cmd 2019 fails, the defaults are used. `2015&par=1` is skipped when the live screen is already in the foreground (the player is simply restarted). No `2015&par=0` is ever sent.

Which stream this camera actually serves is T8.

---

## 8. Settings

Three sources are combined (`c5.d.b1()`, `a5.b`, `y4.k`):

1. **Titles and layout** come from a table shipped in the APK (`assets/caparams/LZXCAM`), listed below.
2. **Option lists** come from the camera: `cmd=3031&str=all`. For each `<Item>`, the `<Cmd>` is the setting id and each `<Id>` is an option label. **A setting the camera does not list is removed from the screen.** So the camera decides what is supported — our app can do the same and never show an unsupported setting.
3. **Current values** come from `cmd=3014`.

To change a setting: `cmd=<setting id>&par=<value>`. The value the app sends is the option's **position** in the 3031 list (0, 1, 2…), not a number supplied by the camera. If the camera's real indexes are not contiguous this is wrong; T7 shows the raw XML so we can check.

Table from the APK (English). "Toggle" sends `par=1`/`par=0`.

| Cmd | Title | Kind |
|---|---|---|
| 2002 | Video Resolution | list |
| 2003 | Cyclic Record (loop length) | list |
| 2004 | WDR | toggle |
| 2007 | Audio | toggle |
| 2008 | Date Stamping | toggle |
| 2019 | Videolapse | list — **id clashes with the live-view-URL query in section 4**; treat as suspect |
| 1002 | Photo Size | list |
| 1007 | White Balance | list |
| 2005 | Exposure | list |
| 1012 | Photo lapse | list |
| 9001–9015 | Gyro, Timelapse, Self-Timer, Anti-Shake, WB, Color, Sharpness, Continue Shot, ISO, Metering, Beep, Frequency, IR, Far Mode, PlaySound | list — action-camera items, probably absent on a dash cam |
| 2006 | Motion detection | toggle |
| 2011 | G-Sensor | list |
| 2012 | Auto-recording | toggle |
| 3007 | Auto Power Off | list |
| 3008 | Language | list |
| 3009 | TV Mode | list |
| 3004 | WiFi Setting | dialog → 3003, 3004, 3021 |
| 3010 | Format | confirm → `par=1` |
| 3011 | Default Setting | confirm → `par=1` |
| 3017 | Surplus Space | read-only |
| 3012 | Firmware Version | read-only |

After changing the resolution from the live screen the app restarts live view (2015).

---

## 9. Notification socket (TCP 3333)

Opened when the live screen starts (`c5.d.g0()`, `y4.l`). The app only reads; it never writes. Each message is an XML fragment with `<Cmd>` and `<Status>`.

| `<Cmd>` | `<Status>` | Meaning in the app |
|---|---|---|
| 3020 | 1 | movie time-lapse started |
| 3020 | 2 | movie time-lapse stopped |
| 3020 | 8 | recording started |
| 3020 | 9 | recording stopped |
| 3020 | 10 | photo time-lapse started |
| 3020 | 11 | photo time-lapse stopped |
| 8008 | seconds | recording elapsed time |

The APK's table also names these values, which the code does not act on: `6` power off, `-7` card full, `-10` battery low, `3` disconnect. A socket close is treated as "camera disconnected" and closes the live screen.

This socket is how we can show recording state without polling. It is optional — 2016 gives the same answer on demand.

---

## 10. Tests to run

Join the camera's Wi-Fi on the phone and open these in the phone browser (turn mobile data off if the page will not load). For each one, send me the text or a screenshot of the page.

| # | Open | What it settles |
|---|---|---|
| T1 | `http://192.168.1.254/?custom=1&cmd=3012` and `…cmd=8005` | Firmware and identity string; confirms the response format. |
| T2 | The file index URL you already use in the browser, and `http://192.168.1.254/?custom=1&cmd=3015` | Real folder names, file naming, how event/locked and photo files are separated, and whether the HTML index or 3015 is the better list source. |
| T3 | `…cmd=2016`, then `…cmd=3015` **while the camera is recording**, then `…cmd=2016` again | Whether listing works during recording, and whether listing stops it (`2016` should still be > 0 and growing). |
| T4 | While recording, copy one file URL from T2 into the browser and download it; note the speed. Then open `<file URL>?custom=1&cmd=4001`. | Download and thumbnails during recording. I will check Range/resume support from the app itself in the first build, since a browser cannot show it reliably. |
| T5 | Stop recording. Open `…cmd=3001&par=2`, download the same file, note the speed. Then `…cmd=3001&par=1`, then `…cmd=2016`. | Whether playback mode is what makes the official app slow, and whether recording restarts by itself after returning to movie mode. |
| T6 | `…cmd=3005&str=2026-11-10` then `…cmd=3006&str=12:00:00` (use the real date and time). Then check the camera screen or record a short clip and look at its timestamp. Repeat once **while recording**. | Whether time sync works, whether it works during recording, and whether drift comes from the camera losing its clock when powered off. |
| T7 | `…cmd=3031&str=all` and `…cmd=3014` | The exact settings this camera supports and their real option indexes. |
| T8 | `…cmd=2019` | The real live-view URLs. |
| T9 | Leave the phone connected without touching it for 5 minutes, then open `…cmd=3012` | Whether the camera drops an idle client (i.e. whether a heartbeat is needed). |

T3, T4 and T6 change nothing on the camera apart from the clock. T5 switches mode and may stop a recording in progress, so run it parked.

---

## 11. What this means for the new app

- Problem 3 looks solvable without stopping recording **if T3 and T4 pass**: list with 3015 (or the HTML index), download with ranged GETs, and never send `3001 par=2`.
- Problem 4: 3005/3006 are known and simple. Since the official app already sends them at connect, T6 matters — a camera with a dead clock battery would lose time at every power-off, and the fix is then "sync on every connection" exactly as requested, with the result checked rather than ignored.
- The settings screen can be built entirely from 3031 + 3014, so it will only show what the camera supports.
- We do not need the 8005 gate, the Ambarella code path, or cmd 8006.
