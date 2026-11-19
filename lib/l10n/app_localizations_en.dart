// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'nCAM';

  @override
  String get cancel => 'Cancel';

  @override
  String get delete => 'Delete';

  @override
  String get save => 'Save';

  @override
  String get retry => 'Retry';

  @override
  String get tryAgain => 'Try again';

  @override
  String get refresh => 'Refresh';

  @override
  String get more => 'More';

  @override
  String get connect => 'Connect';

  @override
  String get starting => 'Starting…';

  @override
  String get front => 'Front';

  @override
  String get rear => 'Rear';

  @override
  String get both => 'Both';

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String get back10 => 'Back 10 seconds';

  @override
  String get forward10 => 'Forward 10 seconds';

  @override
  String get showPassword => 'Show password';

  @override
  String get hidePassword => 'Hide password';

  @override
  String get notConnected => 'Not connected';

  @override
  String get firmware => 'Firmware';

  @override
  String get noSdCard => 'No SD card';

  @override
  String freeSpace(String size) {
    return '$size free';
  }

  @override
  String get unknownDate => 'Unknown date';

  @override
  String get search => 'Search';

  @override
  String get searchHint => 'Search names and dates';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get closeSearch => 'Close search';

  @override
  String fileCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files',
      one: '1 file',
    );
    return '$_temp0';
  }

  @override
  String get settingsTitle => 'Settings';

  @override
  String get diagnosticLog => 'Diagnostic log';

  @override
  String titleWithName(String name, String date) {
    return '$name · $date';
  }

  @override
  String get dayPattern => 'EEE d MMM y';

  @override
  String spanSeconds(int s) {
    return '$s s';
  }

  @override
  String spanMinutes(int m, int s) {
    return '$m min $s s';
  }

  @override
  String spanHours(int h, int m) {
    return '$h h $m min';
  }

  @override
  String spanDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count days',
      one: '1 day',
    );
    return '$_temp0';
  }

  @override
  String get tabLive => 'Live';

  @override
  String get tabRecordings => 'Recordings';

  @override
  String get tabSaved => 'Saved';

  @override
  String get recordingStarted => 'Recording started.';

  @override
  String get recordingStopped => 'Recording stopped.';

  @override
  String get holdToStop => 'Hold the button to stop recording.';

  @override
  String get a11yRecordPaused => 'Recording paused for fast download.';

  @override
  String get a11yRecordUnavailable => 'Record. Not available until connected.';

  @override
  String get a11yStopping => 'Stopping recording.';

  @override
  String get a11yStarting => 'Starting recording.';

  @override
  String get a11yRecording => 'Recording. Press and hold to stop.';

  @override
  String get a11yNotRecording => 'Not recording. Tap to start.';

  @override
  String get defaultCameraName => 'camera';

  @override
  String linkConnected(String name) {
    return 'Connected to $name';
  }

  @override
  String get linkConnectedHint =>
      'Only this app uses the camera\'s Wi-Fi; the rest of the phone stays online.';

  @override
  String linkJoining(String name) {
    return 'Joining $name…';
  }

  @override
  String get linkJoiningHint => 'Android may ask you to confirm.';

  @override
  String linkLost(String name) {
    return 'Lost $name';
  }

  @override
  String get linkLostHint => 'Rejoins when the camera is back in range.';

  @override
  String get linkFirstTime =>
      'Enter the camera\'s Wi-Fi name and password once.';

  @override
  String linkSaved(String name) {
    return 'Saved camera: $name';
  }

  @override
  String get disconnect => 'Disconnect';

  @override
  String get scanNone => 'No networks found. Turn Wi-Fi on, or type the name.';

  @override
  String get scanNoPermission =>
      'Without that permission, networks can\'t be listed. You can type the name.';

  @override
  String scanFailed(String detail) {
    return 'Scan failed: $detail';
  }

  @override
  String connectTo(String name) {
    return 'Connect to $name';
  }

  @override
  String get changeNameOrPassword => 'Change name or password';

  @override
  String get forget => 'Forget';

  @override
  String get cameraWifiName => 'Camera Wi-Fi name';

  @override
  String get findNetworks => 'Find nearby networks';

  @override
  String get password => 'Password';

  @override
  String get nowRecording => 'The camera is recording.';

  @override
  String get notRecordingWarning => 'The camera is NOT recording.';

  @override
  String get startRecording => 'Start recording';

  @override
  String get recording => 'Recording';

  @override
  String get notRecording => 'Not recording';

  @override
  String get sdCardOk => 'SD card OK';

  @override
  String currentClip(String span) {
    return 'Current clip: $span';
  }

  @override
  String get noFileList => 'No file list';

  @override
  String get clockNotSynced => 'Camera clock not synced yet';

  @override
  String get syncOnConnectIsOff => 'Sync on connect is off in Settings.';

  @override
  String get clockSyncFailed => 'Clock sync failed';

  @override
  String clockSyncedAt(String time) {
    return 'Clock synced at $time';
  }

  @override
  String get clockNotChecked =>
      'Previous time unknown: the camera wasn\'t recording.';

  @override
  String get clockWasRight => 'The camera\'s clock was already right.';

  @override
  String clockWasAhead(String span) {
    return 'The camera was $span ahead.';
  }

  @override
  String clockWasBehind(String span) {
    return 'The camera was $span behind.';
  }

  @override
  String get clockNextClip => 'The new time shows from the next clip.';

  @override
  String get syncTime => 'Sync time';

  @override
  String recordingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count recordings',
      one: '1 recording',
    );
    return '$_temp0';
  }

  @override
  String filesAndSize(int count, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files, $size',
      one: '1 file, $size',
    );
    return '$_temp0';
  }

  @override
  String downloadsActive(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count downloads queued',
      one: '1 download running',
    );
    return '$_temp0';
  }

  @override
  String joinFailedHint(String name) {
    return 'Could not join \"$name\". Check that the camera is on and nearby, the password, and Android\'s prompt.';
  }

  @override
  String joinFailed(String name, String detail) {
    return 'Could not join \"$name\": $detail';
  }

  @override
  String cameraNoAnswer(String detail) {
    return 'Joined the Wi-Fi, but the camera didn\'t answer: $detail';
  }

  @override
  String cameraError(String detail) {
    return 'Camera error: $detail';
  }

  @override
  String wifiRefused(String detail) {
    return 'The camera didn\'t accept the new Wi-Fi settings: $detail';
  }

  @override
  String startRefused(String detail) {
    return 'The camera refused to start recording: $detail';
  }

  @override
  String stopRefused(String detail) {
    return 'The camera refused to stop recording: $detail';
  }

  @override
  String startNoAnswer(String detail) {
    return 'Told the camera to start recording, but it didn\'t answer: $detail';
  }

  @override
  String stopNoAnswer(String detail) {
    return 'Told the camera to stop recording, but it didn\'t answer: $detail';
  }

  @override
  String get stillNotRecording => 'The camera accepted, but isn\'t recording.';

  @override
  String get stillRecording => 'The camera accepted, but is still recording.';

  @override
  String listRefusedRecording(String detail) {
    return 'The camera won\'t send its list while recording ($detail).';
  }

  @override
  String listRefused(String detail) {
    return 'The camera sent no file list ($detail). It does this when the card is empty.';
  }

  @override
  String get listRefusedStopped =>
      'The camera sent no list, even with recording stopped.';

  @override
  String listReadFailed(String detail) {
    return 'Could not read the list: $detail';
  }

  @override
  String get recordingDidNotRestart =>
      'Recording didn\'t restart: press the camera\'s record button.';

  @override
  String recordingMaybeOff(String detail) {
    return 'The camera may not be recording: press its record button. ($detail)';
  }

  @override
  String get recordingsTitle => 'Recordings';

  @override
  String get nothingToDownload =>
      'Nothing to download: already saved or queued.';

  @override
  String downloadStartFailed(String detail) {
    return 'Could not start the download: $detail';
  }

  @override
  String get pauseToListTitle => 'Pause recording?';

  @override
  String get pauseToListBody =>
      'Recording stops for a few seconds while the list is read, then restarts. The current clip becomes downloadable too.';

  @override
  String get pauseToListAction => 'Pause and read';

  @override
  String get pauseToListDone => 'List read. Recording again.';

  @override
  String get pauseToList => 'Pause recording to read the list';

  @override
  String get deleteWhileDownloading =>
      'Some of these are downloading. Cancel or wait first.';

  @override
  String deleteFromCameraTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count files from the camera?',
      one: 'Delete 1 file from the camera?',
    );
    return '$_temp0';
  }

  @override
  String get cannotUndo => 'This can\'t be undone.';

  @override
  String get allSavedOnPhone =>
      'All are saved on this phone; those copies stay.';

  @override
  String get noneSavedOnPhone => 'None are saved on this phone.';

  @override
  String someNotSavedOnPhone(int count) {
    return '$count aren\'t saved on this phone.';
  }

  @override
  String deletedFromCamera(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Deleted $count files from the camera.',
      one: 'Deleted 1 file from the camera.',
    );
    return '$_temp0';
  }

  @override
  String deletedSomeFromCamera(int done, int total, String detail) {
    return 'Deleted $done of $total. The camera refused the next: $detail';
  }

  @override
  String get cancelSelection => 'Cancel selection';

  @override
  String get selectAll => 'Select all';

  @override
  String get deleteSelectedFromCamera => 'Delete selected from camera';

  @override
  String get downloadSelected => 'Download selected';

  @override
  String selectedCount(int count) {
    return '$count selected';
  }

  @override
  String get selectSeveral => 'Select several';

  @override
  String get frontAndRear => 'Front + rear';

  @override
  String noMatch(String query) {
    return 'No recording matches \"$query\".';
  }

  @override
  String get readingCard => 'Reading the card…';

  @override
  String get noRecordings => 'No recordings on the card.';

  @override
  String get connectToSeeRecordings =>
      'Connect to the camera to see its recordings.';

  @override
  String get deleteFromCamera => 'Delete from camera';

  @override
  String get recordingNow => 'Recording now. Available when this clip ends.';

  @override
  String clockWasWrongAtStart(String time) {
    return 'The clock was wrong when this started: its file name says $time.';
  }

  @override
  String chipSize(String lens, String size) {
    return '$lens · $size';
  }

  @override
  String get chipDownload => 'Download';

  @override
  String get chipStillRecording => 'Still recording';

  @override
  String chipQueued(String lens) {
    return '$lens · queued';
  }

  @override
  String chipDownloading(String lens, int percent) {
    return '$lens · $percent%';
  }

  @override
  String chipDownloadingStart(String lens) {
    return '$lens · starting';
  }

  @override
  String chipRetrying(String lens, int percent) {
    return '$lens · retrying $percent%';
  }

  @override
  String chipRetryingStart(String lens) {
    return '$lens · retrying';
  }

  @override
  String chipFailed(String lens) {
    return '$lens · failed, tap to resume';
  }

  @override
  String chipSaved(String lens) {
    return '$lens · saved';
  }

  @override
  String get tapToCancel => 'Tap to cancel';

  @override
  String get downloadFailed => 'Download failed';

  @override
  String queueRetrying(String detail) {
    return 'Connection problem, retrying: $detail';
  }

  @override
  String perSecond(String size) {
    return '$size/s';
  }

  @override
  String timeLeft(String span) {
    return '$span left';
  }

  @override
  String queueDownloading(int position, int total, String name) {
    return 'Downloading $position of $total · $name';
  }

  @override
  String get cancelAll => 'Cancel all';

  @override
  String oneDownloadFailed(String detail) {
    return '1 download failed: $detail';
  }

  @override
  String downloadsFailed(int count) {
    return '$count downloads failed';
  }

  @override
  String get resume => 'Resume';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get fastTitle => 'Fast download';

  @override
  String get fastHint => 'Pauses recording while downloading. About 2× faster.';

  @override
  String get fastConfirmTitle => 'Pause recording to download faster?';

  @override
  String get fastConfirmBody =>
      'Nothing is recorded while files download. Recording restarts when the queue ends or is cancelled, or when the app next reconnects.\n\nOnly use this while parked.';

  @override
  String get turnOn => 'Turn on';

  @override
  String get fastPausing => 'Pausing recording for fast download…';

  @override
  String get fastPausedDownloading =>
      'Recording PAUSED while files download. It restarts when they finish.';

  @override
  String get fastPausedIdle =>
      'Recording PAUSED. It wasn\'t restarted after the last fast download.';

  @override
  String get fastResuming => 'Restarting recording…';

  @override
  String get fastFailed =>
      'Recording is still OFF: the app couldn\'t restart it.';

  @override
  String fastFailedDetail(String detail) {
    return 'Recording is still OFF ($detail). Reconnect and try again, or press the camera\'s record button.';
  }

  @override
  String get restartRecording => 'Restart recording';

  @override
  String get savedTitle => 'Saved on this phone';

  @override
  String deleteFromPhoneTitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Delete $count files from this phone?',
      one: 'Delete 1 file from this phone?',
    );
    return '$_temp0';
  }

  @override
  String get deleteFromPhoneBody =>
      'Only the phone\'s copy is removed; the camera\'s stays.';

  @override
  String get deletedFromPhone => 'Deleted from this phone.';

  @override
  String deletedSomeFromPhone(int done, int total) {
    return 'Deleted $done of $total. The rest couldn\'t be removed.';
  }

  @override
  String get lookingForSaved => 'Looking for saved clips…';

  @override
  String get nothingSaved =>
      'Nothing saved yet. Downloaded recordings appear here and in your gallery (Movies/nCAM).';

  @override
  String noSavedMatch(String query) {
    return 'No saved recording matches \"$query\".\nTry a name, a date such as \"17 Nov\" or a time such as \"19:22\".';
  }

  @override
  String get nameRecording => 'Name recording';

  @override
  String get renameRecording => 'Rename recording';

  @override
  String get nameLabel => 'Name';

  @override
  String get nameHint => 'e.g. Near miss on the A1';

  @override
  String get removeName => 'Remove name';

  @override
  String get nameMenu => 'Name…';

  @override
  String get renameMenu => 'Rename…';

  @override
  String get deleteFromPhone => 'Delete from this phone';

  @override
  String get clipNotSaved => 'This clip isn\'t saved on the phone.';

  @override
  String clipPlayFailed(String detail) {
    return 'This clip could not be played: $detail';
  }

  @override
  String get zoomOriginal => 'Original';

  @override
  String get zoomFill => 'Zoomed to fill';

  @override
  String zoomFactor(String factor) {
    return '$factor×';
  }

  @override
  String get liveTitle => 'Live view';

  @override
  String fps(int fps) {
    return '$fps fps';
  }

  @override
  String get liveStarting => 'Starting live view…';

  @override
  String get liveStoppedShort => 'Live view stopped.';

  @override
  String liveStopped(String detail) {
    return 'Live view stopped: $detail';
  }

  @override
  String get liveStreamClosed => 'the camera closed the stream';

  @override
  String get liveConnectionLost => 'Connection lost. Reconnecting…';

  @override
  String get liveRestarting => 'Restarting the connection…';

  @override
  String get liveReconnecting => 'Reconnecting…';

  @override
  String get liveNoPicture => 'The camera isn\'t sending a picture.';

  @override
  String viewNumber(int number) {
    return 'View $number';
  }

  @override
  String viewSwitchFailed(String detail) {
    return 'Could not switch view: $detail';
  }

  @override
  String get pipTooltip => 'Picture-in-picture';

  @override
  String get pipUnavailable =>
      'Picture-in-picture isn\'t available. Allow it for nCAM in Android settings.';

  @override
  String logReadFailed(String detail) {
    return 'Could not read the log: $detail';
  }

  @override
  String get reload => 'Reload';

  @override
  String get saveToDownloads => 'Save to Downloads';

  @override
  String logSaved(String name) {
    return 'Saved to Downloads as $name';
  }

  @override
  String logSaveFailed(String detail) {
    return 'Could not save the log: $detail';
  }

  @override
  String get copyAll => 'Copy all';

  @override
  String get logCopied => 'Log copied.';

  @override
  String get clear => 'Clear';

  @override
  String get logEmpty => 'Nothing logged yet.';

  @override
  String get sectionApp => 'App';

  @override
  String get sectionCamera => 'Camera';

  @override
  String get sectionWifi => 'Wi-Fi';

  @override
  String get sectionStorage => 'Storage';

  @override
  String get sectionDevice => 'Device';

  @override
  String get colours => 'Colours';

  @override
  String get appearance => 'Appearance';

  @override
  String get colorWallpaper => 'Wallpaper';

  @override
  String get colorBlue => 'Blue';

  @override
  String get colorTeal => 'Teal';

  @override
  String get colorGreen => 'Green';

  @override
  String get colorOrange => 'Orange';

  @override
  String get colorRed => 'Red';

  @override
  String get colorPurple => 'Purple';

  @override
  String get modeSystem => 'Follow system';

  @override
  String get modeLight => 'Light';

  @override
  String get modeDark => 'Dark';

  @override
  String get modeBlack => 'Pure black';

  @override
  String get wallpaperNote =>
      'Wallpaper colours need Android 12 or later; otherwise blue is used.';

  @override
  String get cameraIsRecording => 'The camera is recording';

  @override
  String get cameraIsRecordingHint =>
      'If a change stops it, the app restarts recording.';

  @override
  String get autoConnect => 'Connect on start-up';

  @override
  String get autoConnectHint => 'Join the saved camera when the app opens.';

  @override
  String get syncOnConnect => 'Sync time on connect';

  @override
  String get syncOnConnectHint => 'Set the camera clock to the phone\'s.';

  @override
  String get autoPip => 'Auto picture-in-picture';

  @override
  String get autoPipHint => 'Float video when you leave the app.';

  @override
  String get recordButton => 'Record button';

  @override
  String get recordButtonHint => 'Side of the dock';

  @override
  String get sideLeft => 'Left';

  @override
  String get sideRight => 'Right';

  @override
  String get connectToChangeSettings =>
      'Connect on the home page to change camera settings.';

  @override
  String get readingSettings => 'Reading settings…';

  @override
  String get settingsReadFailed => 'Could not read the settings';

  @override
  String get otherValues => 'Other values (read-only)';

  @override
  String get otherValuesHint => 'Reported by the camera with no choices.';

  @override
  String settingNumber(int id) {
    return 'Setting $id';
  }

  @override
  String get fixedOnCamera => 'Fixed on this camera';

  @override
  String get changingSetting => 'Changing setting…';

  @override
  String get changeWifi => 'Change Wi-Fi name and password';

  @override
  String get changeWifiHint =>
      'The camera restarts its Wi-Fi; the app reconnects.';

  @override
  String get changingWifi => 'Changing the camera\'s Wi-Fi…';

  @override
  String wifiChanged(String name) {
    return 'Connected to \"$name\" with the new password.';
  }

  @override
  String get sdCard => 'SD card';

  @override
  String get formatSdCard => 'Format SD card';

  @override
  String get formatSdCardHint => 'Erases every recording on the camera.';

  @override
  String get formatTitle => 'Format the SD card?';

  @override
  String get formatBody =>
      'Erases every recording on the camera; this can\'t be undone. Clips saved on this phone are kept. Recording pauses, then restarts.';

  @override
  String get formatAction => 'Erase everything';

  @override
  String get formatting => 'Formatting the card…';

  @override
  String get restoreFactory => 'Restore factory settings';

  @override
  String get resetTitle => 'Restore factory settings?';

  @override
  String get resetBody =>
      'Camera settings return to their defaults. If the Wi-Fi name and password reset too, reconnect with the defaults.';

  @override
  String get resetAction => 'Reset camera';

  @override
  String get resetting => 'Resetting the camera…';

  @override
  String get wifiDialogTitle => 'Camera Wi-Fi';

  @override
  String get wifiName => 'Wi-Fi name';

  @override
  String get newPassword => 'New password';

  @override
  String get wifiNameRule =>
      'Name: 1–32 letters, digits or symbols, no spaces.';

  @override
  String get wifiPasswordRule =>
      'Password: 8–63 letters, digits or symbols, no spaces.';

  @override
  String get wifiPasswordWarning =>
      'Write it down: if it\'s lost, only the camera\'s reset button gets you back in.';

  @override
  String get change => 'Change';

  @override
  String get settingPhotoSize => 'Photo size';

  @override
  String get settingVideoResolution => 'Video resolution';

  @override
  String get settingExposure => 'Exposure';

  @override
  String get settingRecordAudio => 'Record audio';

  @override
  String get settingAutoPowerOff => 'Auto power off';

  @override
  String get settingLoopRecording => 'Loop recording';

  @override
  String get settingGSensor => 'G-sensor';

  @override
  String get settingDateStamp => 'Date stamp';

  @override
  String get settingWdr => 'WDR';

  @override
  String get settingMotionDetection => 'Motion detection';

  @override
  String get settingAutoRecording => 'Auto recording';

  @override
  String get settingLanguage => 'Language';

  @override
  String get settingTvMode => 'TV mode';

  @override
  String optionMinutes(int count) {
    return '$count min';
  }

  @override
  String get optionOn => 'On';

  @override
  String get optionOff => 'Off';

  @override
  String get recordingRestarted =>
      'Recording stopped for this and was restarted.';

  @override
  String get recordingNotRestarted =>
      'Recording stopped and did NOT restart. Press the camera\'s record button.';

  @override
  String changeRefusedRecording(String detail) {
    return 'The camera refused the change ($detail). It may only accept it when not recording.';
  }

  @override
  String changeRefused(String detail) {
    return 'The camera refused the change ($detail).';
  }

  @override
  String cameraUnreachable(String detail) {
    return 'Could not reach the camera: $detail';
  }

  @override
  String formatRefused(String detail) {
    return 'The camera refused to format the card ($detail).';
  }

  @override
  String get formatDone => 'The card was formatted.';

  @override
  String get recordingRestartedShort => 'Recording restarted.';

  @override
  String formatFailed(String detail) {
    return 'Formatting went wrong: $detail. Check that the camera is recording.';
  }

  @override
  String get resetDone =>
      'Factory settings restored. If the camera\'s Wi-Fi reset too, enter the defaults on the home page.';

  @override
  String resetRefused(String detail) {
    return 'The camera refused the reset ($detail).';
  }

  @override
  String resetUnconfirmed(String detail) {
    return 'Reset sent, but the camera didn\'t confirm: $detail';
  }
}
