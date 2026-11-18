# nCAM — real-world test plan

Tests to run on the real phone (Galaxy S24 Ultra, Android 17) and the real camera (NoodleCam, firmware `DVR52AFHW3_YL_V3.19_TS`). The automated tests cover parsing and app logic against a fake camera; everything below is what only the real devices can prove.

## How to use this

- Work top to bottom. Sections A–G were already run during development; their results are filled in. Sections H–K are new.
- Fill in the **Result** column: `Pass`, `Fail`, or `Skip` with a reason.
- **On a failure**, note the test ID and send a screenshot of the app. For anything involving the camera's behaviour, also say what the camera's own screen showed.
- Tests marked **⚠ destructive** change or erase things on the camera. Read the note before running them.
- Tests marked **parked** stop recording for a while. Do not run them while driving.

**Result legend used below**

| Mark | Meaning |
|---|---|
| Pass (reported) | You ran it during development and said it worked. |
| Pass (reported, detail wanted) | You said the step worked, but one observation was never written down. The test says which. |
| *(blank)* | Not run yet. |

## Setup before each session

1. Install the latest `build\app\outputs\flutter-apk\app-release.apk`.
2. In Android's Wi-Fi settings, make sure the phone is **not** joined to NoodleCam (forget it there if it is listed). The app joins by itself; a system-level join defeats the routing tests.
3. Camera powered and recording, unless the test says otherwise.
4. Mobile data on.

---

## A. Connecting (goal 1: no trip to Android settings)

| ID | Do | Expect | Result |
|---|---|---|---|
| A1 | First run: enter `NoodleCam` and the password, tap Connect. | Android asks to confirm the network. Then "Connected to NoodleCam" and the status cards within a few seconds. | Pass (reported) |
| A2 | On the entry form, tap the search icon. | Asks for the nearby-devices permission, then lists NoodleCam. | Pass (reported) |
| A3 | Close the app fully and reopen it. | Rejoins without typing anything. | Pass (reported) |
| A4 | With the app open, power the camera off for a minute, then on. | "Lost NoodleCam", then an automatic rejoin and a fresh clock sync. | Pass (reported) |
| A5 | Tap Disconnect, then "Connect to NoodleCam". | Disconnects and reconnects with one tap. | |
| A6 | Tap "Change name or password", enter a wrong password, Connect. | A clear "Could not join" message within about a minute. Nothing is saved; the old saved camera still works. | |
| A7 | Camera off. Open the app. | "Joining…" and then a "Could not join" message. No crash, no endless spinner. | |
| A8 | Deny the nearby-devices permission, then tap the search icon. | A message that networks cannot be listed, and typing the name still works. | |
| A9 | Tap Forget, then set the camera up again from scratch. | Entry form returns; A1 works again. | |

## B. Internet stays up (goal 2: only camera traffic uses the camera)

| ID | Do | Expect | Result |
|---|---|---|---|
| B1 | Connected, on mobile data only: open a web page in a browser. | Page loads. | Pass (reported) |
| B2 | Connected, with home Wi-Fi also on: open a web page. | Page loads. | Pass (reported) |
| B3 | Connected: use an app that needs internet continuously (music streaming, maps navigation) for 10 minutes while nCAM downloads a clip. | The other app never drops; the download keeps running. | |
| B4 | Connected: receive a message in a chat app. | Arrives normally. | |
| B5 | Connected: in a browser, open `http://192.168.1.254`. | Does **not** load. Only nCAM can reach the camera, which is the intended design. | |
| B6 | Disconnect in nCAM. Check the status bar and Android's Wi-Fi settings. | The phone is no longer on NoodleCam. | |

## C. Clock sync (goal 4: correct timestamps)

| ID | Do | Expect | Result |
|---|---|---|---|
| C1 | Connect while the camera records. Read the time card. | "Clock synced at …" and either "already right" or how far off the camera was. | Pass (reported) |
| C2 | Wait for the next clip to start, tap Refresh, open Recordings. | The newest file name carries the right date and time. | Pass (reported) |
| C3 | Tap "Sync time". | Card updates to the new time. | Pass (reported) |
| C4 | Leave the camera unpowered overnight (or as long as it normally sits). Connect and read the time card **before** doing anything else. | Note what it says the camera was off by. This measures real drift. Write the figure here. | |
| C5 | Repeat C4 on three different days. | Three figures. If they are all small (seconds), drift is not the cause of wrong timestamps; if one is a month or a year, tell me the dates. | |
| C6 | Connect while the camera is **not** recording. | "Clock synced", with a note that the previous time could not be checked. The next clip is named correctly. | |
| C7 | Open the official VF Cam app once, connect with it, close it. Then connect with nCAM and read the time card. | Tells us whether the official app is what set the clock a month back on 11 November. Write down what the card says. | |
| C8 | Settings → turn off "Sync time on connect". Disconnect and connect again. | The time card says "Sync on connect is off in Settings." and the camera's clock is left as it was. "Sync time" still works. Turn the switch back on afterwards (it is on by default). | |

## D. Recordings and downloads (goal 3: download while recording)

| ID | Do | Expect | Result |
|---|---|---|---|
| D1 | Open Recordings while recording. | Dates correct, front and rear paired, newest clip marked "Recording now". | Pass (reported) |
| D2 | Tap one clip's "Front" chip. | Progress at around 1.3 MB/s, then "saved". The file plays from the gallery (`Movies/nCAM`). | Pass (reported) |
| D3 | Select three or four recordings and download. | They run one after another. | Pass (reported) |
| D4 | Start a large clip, turn the screen off for a minute. | Still downloading when you look again. | Pass (reported) |
| D5 | During a large download, power the camera off about 20 seconds, then on. | "retrying", then the percentage continues from where it was. | Pass (reported) |
| D6 | Leave the camera off two minutes during a download. Power on, wait for reconnect, tap the failed chip. | Ends as "failed, tap to resume", then resumes. | Pass (reported) |
| D7 | Cancel one running download; then "Cancel all" on a queue. | Stops; chips return to the download icon. | Pass (reported) |
| D8 | Throughout D1–D7, watch the camera. | It never stops recording. | Pass (reported) |
| D9 | Download a full 10-minute clip (about 930 MB). Compare its size on the phone with the size shown in the list. Play it to the end and seek to several points. | Same size; plays through with no corruption. | |
| D10 | Set the filter to Rear, Select all, Download. | Only rear clips are queued. | |
| D11 | Download a clip, then tap Refresh. | Still shows "saved", not the download icon. | |
| D12 | Wait until the clip marked "Recording now" finishes (a new one starts), Refresh, then download the finished one. | It becomes downloadable and its saved size matches. | |
| D13 | Queue five clips, then force-stop the app from Android settings. Reopen, reconnect, queue the same five. | Clips that were finished show "saved"; the interrupted one resumes from part-way, not from zero. | |
| D14 | Deny the notification permission when first asked, then download. | Downloads still work; there is just no progress notification. | |
| D15 | During a download, take a phone call or switch to another app for five minutes. | Download continues. | |
| D16 | Fill the phone until less than 1 GB is free, then download a large clip. | Fails with a readable message. No crash, and no half-file appears in the gallery. | |

## E. Fast download — **parked**

| ID | Do | Expect | Result |
|---|---|---|---|
| E1 | Turn Fast download on (confirm the dialog), download two or three clips. | "Recording is PAUSED" banner, roughly double speed. At the end "Restarting recording…", then the camera records and the home screen says "Recording". | Pass (reported) |
| E2 | Start a fast download, tap "Cancel all". | Recording restarts. | Pass (reported) |
| E3 | With several files queued, turn the switch off. | Recording restarts before the next file; the rest download at normal speed. | Pass (reported) |
| E4 | Start a fast download, swipe the app away from recents. Reopen. | After reconnecting, recording restarts without you doing anything. | Pass (reported) |
| E5 | Start a fast download, power the camera off for a few minutes, then on. | Banner turns red, then clears once the app reconnects. | Pass (reported) |
| E6 | Switch off: download normally. | Recording keeps running. | Pass (reported) |
| E7 | After E1, look at the last clip before the pause and the first after it. | Both play. Write down the gap in recording time between them. | |
| E8 | Start a fast download, then walk out of Wi-Fi range with the phone for 10 minutes without closing the app. Come back. | Find out whether the camera resumed by itself while you were away. On return the app must restart recording if it had not. Write down what the camera did. | |
| E9 | Fast download with a queue long enough to take 20+ minutes. | Stays paused the whole time and restarts at the end. | |

## F. Live view

| ID | Do | Expect | Result |
|---|---|---|---|
| F1 | Open Live view while recording. | A picture appears. | Pass (reported, detail wanted): how many seconds until the picture, what fps is shown, and how far behind real time (wave a hand at the lens). |
| F2 | Go back to the home screen. | Still "Recording", clip time still counting. | Pass (reported) |
| F3 | Tap View 1, View 2, View 3. | The picture changes. | Pass (reported, detail wanted): what each view shows, and whether the camera's own screen changes too. I need this to name the buttons. |
| F4 | Start a download, then open Live view. | Both keep working. | Pass (reported, detail wanted): the download speed while live view is open. |
| F5 | Open and close Live view five times. | Starts cleanly each time. | Pass (reported) |
| F6 | Rotate the phone sideways. | Picture fills the screen. | Pass (reported) |
| F7 | Leave Live view open for 15 minutes. | Picture keeps moving, the phone's screen stays on, the app does not slow down or heat the phone unusually. | |
| F8 | With Live view open, power the camera off, then on. | "Reconnecting…", then either the picture returns or a "Try again" button that works once the camera is back. | |
| F9 | Open Live view during a **fast** download (recording paused). | Either a picture or a clear message. Write down which. | |

## G. Thumbnails and deleting from the camera

Results here were reported as working in general; the individual checks were not recorded, so run any you have not specifically done.

| ID | Do | Expect | Result |
|---|---|---|---|
| G1 | Open Recordings while recording. | Thumbnails appear one by one. Note roughly how long each takes and whether any stay as a grey film icon. | Pass (reported, detail wanted) |
| G2 | Leave and reopen Recordings. | Thumbnails appear instantly. | |
| G3 | Start a download and scroll the list. | Both keep working. Note whether the download slows. | |
| G4 | ⚠ destructive. On a clip you do not need: three-dot menu, "Delete from camera". | "Deleted 2 files", recording gone from the list. | |
| G5 | After G4, check the camera's own file list (official app or its screen). | The files are really gone. | |
| G6 | ⚠ destructive. Select two or three unwanted recordings, tap the bin. | All deleted. | |
| G7 | ⚠ destructive. Run G4 while the camera records. | Deleted, and the camera keeps recording. If the camera refuses, write down the message. | |
| G8 | ⚠ destructive. Filter Rear, delete one recording, switch back to "Front + rear". | The front clip remains on its own. | |
| G9 | Try to delete a clip that is downloading. | Refused with a message. | |
| G10 | Look at the clip marked "Recording now". | It has no three-dot menu and cannot be selected. | |
| G11 | ⚠ destructive. Delete a recording that is saved on the phone. | The dialog says the phone copy is kept; afterwards it is still in "Saved on this phone" and plays. | |

---

## H. Saved clips and the player (new)

| ID | Do | Expect | Result |
|---|---|---|---|
| H1 | Camera off. Open "Saved on this phone". | Lists every downloaded clip by date, with thumbnails. | |
| H2 | Play a clip. | Picture and sound. Play/pause, the seek bar and both 10-second skips work. | |
| H3 | On a recording with front and rear saved, switch Front/Rear mid-playback. | Continues from the same moment on the other camera. | |
| H4 | Play a full 10-minute clip to the end. | No stall or crash; at the end the play button restarts it. | |
| H5 | Rotate the phone during playback. | Picture resizes and playback continues. | |
| H6 | Connected: in Recordings, tap a chip that says "saved". | Plays that clip. | |
| H7 | Three-dot menu, "Delete from this phone". | Gone from the list and from the gallery. The camera's copy is untouched: Recordings shows it with a download icon again. | |
| H8 | Open the same clips in Samsung Gallery. | They are in `Movies/nCAM` and play there too. | |
| H9 | Play a clip, press Home, return to the app. | No crash; playback can be resumed. | |
| H10 | On a recording with front and rear saved, tap **Both** mid-playback. | Both clips play from the same moment, front above rear in portrait and side by side in landscape. Only the front clip's sound. Play/pause, the seek bar and the 10-second skips move both. | |
| H11 | Let Both play for a full 10-minute clip. | The two pictures stay in step (a car passing should show on the rear just after the front, not seconds apart). | |
| H12 | Both playing: press Home. | The floating window shows the two pictures side by side. | |
| H13 | Both playing: pause, then play, several times; drag the seek bar; use the 10-second skips. | One press each time. Both pictures move and keep going together; neither freezes or replays the same second. | |
| H14 | Rotate to landscape (one clip, then Both). | The clips fill the screen and the status and navigation bars hide. The controls fade after 3 s of playing; a tap on the picture brings them back. Rotating back restores the bars. | |
| H15 | Saved → three-dot menu (or long-press) on a recording → "Name…", type a name, Save. | The name is the tile's title with the time under it. It also shows in the player's title and, when connected, on that recording in Recordings. It is still there after closing and reopening the app. | |
| H16 | Same menu → "Rename…": change it; then "Remove name". | The new name shows; after removing, the tile shows the time again. | |
| H17 | Type in the search box: part of a name; a date such as "17 Nov", "november", "2026-11-17" or "11/17"; a time such as "19:22". | Only matching recordings stay, under their day headings. Something that matches nothing says so; the clear button brings everything back. | |
| H18 | Delete a named recording from the phone, then download it again. | It comes back without the old name. | |
| H19 | Connected: Recordings → search icon, then search by a name, a date or a time (as in H17). Then select several → Select all. | Only matching recordings show; Select all picks only those. The ✕ (or Back) closes the search and shows everything again. | |

## I. Settings (new)

Tests I1–I4 are safe. I5–I7 are **⚠ destructive** and each has its own warning.

| ID | Do | Expect | Result |
|---|---|---|---|
| I1 | Open settings (gear icon). | Record audio and Auto power off are editable. Video resolution, Photo size and Exposure show "Fixed on this camera". G-sensor and loop recording appear only under "Other values (read-only)". | |
| I2 | While recording, turn Record audio off. Record a minute, turn it back on, record another minute. Download both clips. | First clip silent, second has sound. Write down whether the camera accepted the change during recording, and whether recording continued or was restarted by the app. | |
| I3 | Change Auto power off to 3 min and back. | Value changes and sticks after leaving and reopening settings. The first option is labelled "On" because that is the camera's own label; if you learn what it means, write it here. | |
| I4 | Power-cycle the camera, reopen settings. | The values from I2 and I3 survived. | |
| I5 | ⚠ destructive. **Wi-Fi change.** A mistake can lock you out until you press the camera's reset button, so do this within reach of it and write the new password down first. Change the name to something new with a new 8+ character password. | "Changing the camera's Wi-Fi…", then "Connected to …" under the new name. Closing and reopening the app reconnects with the new details. Then change it back. | |
| I6 | ⚠ destructive. **Format.** Erases the whole card; download what you want first. Run it while recording. | Recording stops, the card is formatted, recording restarts. Recordings then shows only the new clip. | |
| I7 | ⚠ destructive. **Factory reset.** May return the Wi-Fi name and password to the defaults; only run it if you know them. | A message that the reset was done or sent. Write down what was reset, including whether the Wi-Fi details changed, and whether the camera resumed recording. | |
| I8 | Open the Wi-Fi dialog and try a 5-character password. | Rejected with a message; nothing is sent. | |
| I9 | Cancel each of the three confirmation dialogs (format, reset, Wi-Fi). | Nothing happens to the camera. | |

## J. Stability and everyday use (new)

These are the ones that decide whether the app can replace the official one.

| ID | Do | Expect | Result |
|---|---|---|---|
| J1 | **A normal week.** Use only nCAM for a week: connect after drives, download what you want. | No need to open the official app or Android's Wi-Fi settings even once. Note every moment you were tempted to. | |
| J2 | **Long queue.** Queue everything on the card (normal mode) and leave the phone alone with the screen off. | The whole queue completes. Write down the total size and time. | |
| J3 | **Drive away.** Start a normal download in the car, then walk away with the phone until out of range, and come back 15 minutes later. | Failed files resume when tapped; the camera recorded the whole time. | |
| J4 | **Engine start.** With the app already open on the phone, start the car so the camera boots. | The app joins by itself within about a minute and syncs the clock. | |
| J5 | **Engine off.** Turn the car off while connected. | "Lost NoodleCam"; no crash, no battery drain from endless retries over the next hour (check the battery usage screen). | |
| J6 | **Phone restart.** Restart the phone, open the app. | Reconnects with the saved details. | |
| J7 | **Overnight.** Leave the app open in the background overnight with the camera off. | Next morning it is still responsive and has used little battery. | |
| J8 | **Two phones.** With nCAM connected, try to connect a second device to NoodleCam. | Find out whether the camera allows two clients. Write down what happens to nCAM. | |
| J9 | **Home Wi-Fi nearby.** In the garage, in range of both home Wi-Fi and the camera, connect and download. | Works; home Wi-Fi stays connected for everything else. | |
| J10 | **No SD card.** Remove the card, power the camera, connect. | "No SD card" on the home screen, an empty Recordings list, no crash. | |
| J11 | **Full card / loop.** Let the camera run until it starts overwriting old clips. Refresh Recordings before and after. | Old clips disappear from the list without errors; a download of a clip that was just overwritten fails with "the camera no longer has this file". | |
| J12 | **Dark mode and large text.** Switch the phone to dark mode and to the largest font size; visit every screen. | Everything readable, nothing cut off or overlapping. | |
| J13 | **Rapid use.** Tap quickly between Recordings, Live view, Settings and back, 20 times, during a download. | No crash, no stuck spinner; the download is unaffected. | |
| J14 | **Recording is sacred.** At the end of each test day, check the card. | There is a continuous run of clips covering every period the camera was powered, except the deliberate pauses in section E and I6. | |

## L. Road use (added 2026-11-13)

| ID | Do | Expect | Result |
|---|---|---|---|
| L1 | Look at the bottom dock on every page. | Live, Recordings, Record, Saved, Settings are always there; back (arrow or system) returns to the home page. | |
| L2 | Camera recording: tap the Record button once. | Light vibration and "Hold the button to stop recording". Recording continues. | |
| L3 | Hold the Record button. | A ring fills over 1.5 s, a strong vibration, then "Recording stopped". Letting go early stops nothing. | |
| L4 | Camera stopped: tap the Record button. | Recording starts; the button turns red and says "Hold to stop". | |
| L5 | Watch "Current clip" on the home page for a minute, including when a new 10-minute clip starts. | Counts up every second and drops back to a few seconds at the new clip, without reconnecting. | |
| L6 | Live view open: walk out of Wi-Fi range for a minute, then back. | "Camera connection lost. Reconnecting…", then the picture returns by itself. No Disconnect needed. | |
| L7 | Live view open for 20 minutes while driving. | If the picture drops, it comes back by itself. Save the log afterwards (L9) either way. | |
| L8 | During a cut-out, tap "Try again". | The app rebuilds the camera connection and the picture returns. | |
| L9 | Diagnostic log → download icon. | "Saved to Downloads as nCam-….log"; the file is in the phone's Downloads folder and opens in a text viewer. No permission prompt. | |
| L10 | Turn on the largest font size; look at the dock and home page. | Nothing cut off or overlapping. | |
| L11 | Press and hold the Record button with your thumb, with it on the right and then on the left (Settings). | The button grows to about twice its size above your thumb while pressed, so the stop icon and the ring stay visible; it stays on the screen and shrinks back when you let go. | |

## M. Appearance (added 2026-11-13)

| ID | Do | Expect | Result |
|---|---|---|---|
| M1 | Fresh install, open the app. | Colours match your wallpaper (Material You). | |
| M2 | Change the phone's wallpaper to one with different colours, reopen the app. | The app's colours follow. | |
| M3 | Settings → Colours → each preset, then back to Wallpaper. | The whole app changes at once; the choice survives closing the app. | |
| M4 | Settings → Appearance → Light, Dark, Pure black, Follow system. | Pure black has true black backgrounds with faintly lifted cards and dock; Follow system tracks the phone's dark mode. | |
| M5 | Camera off: open Settings from the dock. | Colours and Appearance work; the camera part says "Not connected". | |

## K. Acceptance: the four original problems

Fill this in last. Each line passes only if every listed test passed.

| Goal | Proven by | Result |
|---|---|---|
| 1. Connect from inside the app, credentials remembered | A1–A9, J4, J6 | |
| 2. Internet keeps working while connected | B1–B6, J9 | |
| 3. Download while recording, batch, progress, resume | D1–D16, J2, J3, J14 | |
| 4. Clock synced on every connection and on demand | C1–C7 | |
| Feature parity: live view, browse, play, delete, settings | F, G, H, I | |
| Stable enough to replace the official app | J1–J14 | |

## Observations I still need

These are not pass/fail; they are facts about the camera that the code cannot tell me.

| # | Question | Where it comes up | Your answer |
|---|---|---|---|
| 1 | What do View 1, 2 and 3 show? Does the camera's own screen change? | F3 | |
| 2 | How long until the live picture appears, and what fps? | F1 | |
| 3 | How far was the camera's clock off after sitting unpowered? | C4, C5 | |
| 4 | Does the official app set the clock a month back? | C7 | |
| 5 | Does the camera accept setting changes while recording? | I2 | |
| 6 | Does the camera resume recording by itself if the phone leaves during a fast download? | E8 | |
| 7 | How long does each thumbnail take while recording? | G1 | |
| 8 | Does the camera allow deleting files while recording? | G7 | |
| 9 | What does the "On" option of Auto power off do? | I3 | |
| 10 | Does a factory reset change the Wi-Fi name and password? | I7 | |
