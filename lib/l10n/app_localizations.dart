import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[Locale('en')];

  /// App name in the title bar.
  ///
  /// In en, this message translates to:
  /// **'nCAM'**
  String get appTitle;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get tryAgain;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// Tooltip of a three-dot menu.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get more;

  /// No description provided for @connect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connect;

  /// No description provided for @starting.
  ///
  /// In en, this message translates to:
  /// **'Starting…'**
  String get starting;

  /// The front camera.
  ///
  /// In en, this message translates to:
  /// **'Front'**
  String get front;

  /// The rear camera.
  ///
  /// In en, this message translates to:
  /// **'Rear'**
  String get rear;

  /// Front and rear together.
  ///
  /// In en, this message translates to:
  /// **'Both'**
  String get both;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @back10.
  ///
  /// In en, this message translates to:
  /// **'Back 10 seconds'**
  String get back10;

  /// No description provided for @forward10.
  ///
  /// In en, this message translates to:
  /// **'Forward 10 seconds'**
  String get forward10;

  /// No description provided for @showPassword.
  ///
  /// In en, this message translates to:
  /// **'Show password'**
  String get showPassword;

  /// No description provided for @hidePassword.
  ///
  /// In en, this message translates to:
  /// **'Hide password'**
  String get hidePassword;

  /// No description provided for @notConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get notConnected;

  /// No description provided for @firmware.
  ///
  /// In en, this message translates to:
  /// **'Firmware'**
  String get firmware;

  /// No description provided for @noSdCard.
  ///
  /// In en, this message translates to:
  /// **'No SD card'**
  String get noSdCard;

  /// Free space on the SD card, e.g. "113.0 GB free".
  ///
  /// In en, this message translates to:
  /// **'{size} free'**
  String freeSpace(String size);

  /// No description provided for @unknownDate.
  ///
  /// In en, this message translates to:
  /// **'Unknown date'**
  String get unknownDate;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search names and dates'**
  String get searchHint;

  /// No description provided for @closeSearch.
  ///
  /// In en, this message translates to:
  /// **'Close search'**
  String get closeSearch;

  /// No description provided for @fileCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file} other{{count} files}}'**
  String fileCount(int count);

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @diagnosticLog.
  ///
  /// In en, this message translates to:
  /// **'Diagnostic log'**
  String get diagnosticLog;

  /// Pattern for day headings, e.g. "Wed 11 Nov 2026". Uses the letters of the intl package's DateFormat (EEE weekday, d day, MMM month, y year).
  ///
  /// In en, this message translates to:
  /// **'EEE d MMM y'**
  String get dayPattern;

  /// A duration under a minute.
  ///
  /// In en, this message translates to:
  /// **'{s} s'**
  String spanSeconds(int s);

  /// A duration under an hour.
  ///
  /// In en, this message translates to:
  /// **'{m} min {s} s'**
  String spanMinutes(int m, int s);

  /// A duration under a day.
  ///
  /// In en, this message translates to:
  /// **'{h} h {m} min'**
  String spanHours(int h, int m);

  /// No description provided for @spanDays.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 day} other{{count} days}}'**
  String spanDays(int count);

  /// Dock button: live view.
  ///
  /// In en, this message translates to:
  /// **'Live'**
  String get tabLive;

  /// Dock button: the camera's recordings.
  ///
  /// In en, this message translates to:
  /// **'Recordings'**
  String get tabRecordings;

  /// Dock button: recordings saved on the phone.
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get tabSaved;

  /// No description provided for @recordingStarted.
  ///
  /// In en, this message translates to:
  /// **'Recording started.'**
  String get recordingStarted;

  /// No description provided for @recordingStopped.
  ///
  /// In en, this message translates to:
  /// **'Recording stopped.'**
  String get recordingStopped;

  /// No description provided for @holdToStop.
  ///
  /// In en, this message translates to:
  /// **'Hold the button to stop recording.'**
  String get holdToStop;

  /// Screen reader.
  ///
  /// In en, this message translates to:
  /// **'Recording paused for fast download.'**
  String get a11yRecordPaused;

  /// Screen reader.
  ///
  /// In en, this message translates to:
  /// **'Record. Not available until connected.'**
  String get a11yRecordUnavailable;

  /// Screen reader.
  ///
  /// In en, this message translates to:
  /// **'Stopping recording.'**
  String get a11yStopping;

  /// Screen reader.
  ///
  /// In en, this message translates to:
  /// **'Starting recording.'**
  String get a11yStarting;

  /// Screen reader.
  ///
  /// In en, this message translates to:
  /// **'Recording. Press and hold to stop.'**
  String get a11yRecording;

  /// Screen reader.
  ///
  /// In en, this message translates to:
  /// **'Not recording. Tap to start.'**
  String get a11yNotRecording;

  /// Used for {name} when no camera is saved.
  ///
  /// In en, this message translates to:
  /// **'camera'**
  String get defaultCameraName;

  /// No description provided for @linkConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected to {name}'**
  String linkConnected(String name);

  /// No description provided for @linkConnectedHint.
  ///
  /// In en, this message translates to:
  /// **'Only this app uses the camera\'s Wi-Fi; the rest of the phone stays online.'**
  String get linkConnectedHint;

  /// No description provided for @linkJoining.
  ///
  /// In en, this message translates to:
  /// **'Joining {name}…'**
  String linkJoining(String name);

  /// No description provided for @linkJoiningHint.
  ///
  /// In en, this message translates to:
  /// **'Android may ask you to confirm.'**
  String get linkJoiningHint;

  /// No description provided for @linkLost.
  ///
  /// In en, this message translates to:
  /// **'Lost {name}'**
  String linkLost(String name);

  /// No description provided for @linkLostHint.
  ///
  /// In en, this message translates to:
  /// **'Rejoins when the camera is back in range.'**
  String get linkLostHint;

  /// No description provided for @linkFirstTime.
  ///
  /// In en, this message translates to:
  /// **'Enter the camera\'s Wi-Fi name and password once.'**
  String get linkFirstTime;

  /// No description provided for @linkSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved camera: {name}'**
  String linkSaved(String name);

  /// No description provided for @disconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get disconnect;

  /// No description provided for @scanNone.
  ///
  /// In en, this message translates to:
  /// **'No networks found. Turn Wi-Fi on, or type the name.'**
  String get scanNone;

  /// No description provided for @scanNoPermission.
  ///
  /// In en, this message translates to:
  /// **'Without that permission, networks can\'t be listed. You can type the name.'**
  String get scanNoPermission;

  /// No description provided for @scanFailed.
  ///
  /// In en, this message translates to:
  /// **'Scan failed: {detail}'**
  String scanFailed(String detail);

  /// No description provided for @connectTo.
  ///
  /// In en, this message translates to:
  /// **'Connect to {name}'**
  String connectTo(String name);

  /// No description provided for @changeNameOrPassword.
  ///
  /// In en, this message translates to:
  /// **'Change name or password'**
  String get changeNameOrPassword;

  /// Forget the saved camera.
  ///
  /// In en, this message translates to:
  /// **'Forget'**
  String get forget;

  /// No description provided for @cameraWifiName.
  ///
  /// In en, this message translates to:
  /// **'Camera Wi-Fi name'**
  String get cameraWifiName;

  /// No description provided for @findNetworks.
  ///
  /// In en, this message translates to:
  /// **'Find nearby networks'**
  String get findNetworks;

  /// No description provided for @password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get password;

  /// No description provided for @nowRecording.
  ///
  /// In en, this message translates to:
  /// **'The camera is recording.'**
  String get nowRecording;

  /// No description provided for @notRecordingWarning.
  ///
  /// In en, this message translates to:
  /// **'The camera is NOT recording.'**
  String get notRecordingWarning;

  /// No description provided for @startRecording.
  ///
  /// In en, this message translates to:
  /// **'Start recording'**
  String get startRecording;

  /// No description provided for @recording.
  ///
  /// In en, this message translates to:
  /// **'Recording'**
  String get recording;

  /// No description provided for @notRecording.
  ///
  /// In en, this message translates to:
  /// **'Not recording'**
  String get notRecording;

  /// No description provided for @sdCardOk.
  ///
  /// In en, this message translates to:
  /// **'SD card OK'**
  String get sdCardOk;

  /// How long the clip being recorded is, e.g. "4 min 10 s".
  ///
  /// In en, this message translates to:
  /// **'Current clip: {span}'**
  String currentClip(String span);

  /// No description provided for @noFileList.
  ///
  /// In en, this message translates to:
  /// **'No file list'**
  String get noFileList;

  /// No description provided for @clockNotSynced.
  ///
  /// In en, this message translates to:
  /// **'Camera clock not synced yet'**
  String get clockNotSynced;

  /// No description provided for @syncOnConnectIsOff.
  ///
  /// In en, this message translates to:
  /// **'Sync on connect is off in Settings.'**
  String get syncOnConnectIsOff;

  /// No description provided for @clockSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Clock sync failed'**
  String get clockSyncFailed;

  /// No description provided for @clockSyncedAt.
  ///
  /// In en, this message translates to:
  /// **'Clock synced at {time}'**
  String clockSyncedAt(String time);

  /// No description provided for @clockNotChecked.
  ///
  /// In en, this message translates to:
  /// **'Previous time unknown: the camera wasn\'t recording.'**
  String get clockNotChecked;

  /// No description provided for @clockWasRight.
  ///
  /// In en, this message translates to:
  /// **'The camera\'s clock was already right.'**
  String get clockWasRight;

  /// No description provided for @clockWasAhead.
  ///
  /// In en, this message translates to:
  /// **'The camera was {span} ahead.'**
  String clockWasAhead(String span);

  /// No description provided for @clockWasBehind.
  ///
  /// In en, this message translates to:
  /// **'The camera was {span} behind.'**
  String clockWasBehind(String span);

  /// No description provided for @clockNextClip.
  ///
  /// In en, this message translates to:
  /// **'The new time shows from the next clip.'**
  String get clockNextClip;

  /// No description provided for @syncTime.
  ///
  /// In en, this message translates to:
  /// **'Sync time'**
  String get syncTime;

  /// No description provided for @recordingCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 recording} other{{count} recordings}}'**
  String recordingCount(int count);

  /// No description provided for @filesAndSize.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 file, {size}} other{{count} files, {size}}}'**
  String filesAndSize(int count, String size);

  /// No description provided for @downloadsActive.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 download running} other{{count} downloads queued}}'**
  String downloadsActive(int count);

  /// No description provided for @joinFailedHint.
  ///
  /// In en, this message translates to:
  /// **'Could not join \"{name}\". Check that the camera is on and nearby, the password, and Android\'s prompt.'**
  String joinFailedHint(String name);

  /// No description provided for @joinFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not join \"{name}\": {detail}'**
  String joinFailed(String name, String detail);

  /// No description provided for @cameraNoAnswer.
  ///
  /// In en, this message translates to:
  /// **'Joined the Wi-Fi, but the camera didn\'t answer: {detail}'**
  String cameraNoAnswer(String detail);

  /// No description provided for @cameraError.
  ///
  /// In en, this message translates to:
  /// **'Camera error: {detail}'**
  String cameraError(String detail);

  /// No description provided for @wifiRefused.
  ///
  /// In en, this message translates to:
  /// **'The camera didn\'t accept the new Wi-Fi settings: {detail}'**
  String wifiRefused(String detail);

  /// No description provided for @startRefused.
  ///
  /// In en, this message translates to:
  /// **'The camera refused to start recording: {detail}'**
  String startRefused(String detail);

  /// No description provided for @stopRefused.
  ///
  /// In en, this message translates to:
  /// **'The camera refused to stop recording: {detail}'**
  String stopRefused(String detail);

  /// No description provided for @startNoAnswer.
  ///
  /// In en, this message translates to:
  /// **'Told the camera to start recording, but it didn\'t answer: {detail}'**
  String startNoAnswer(String detail);

  /// No description provided for @stopNoAnswer.
  ///
  /// In en, this message translates to:
  /// **'Told the camera to stop recording, but it didn\'t answer: {detail}'**
  String stopNoAnswer(String detail);

  /// No description provided for @stillNotRecording.
  ///
  /// In en, this message translates to:
  /// **'The camera accepted, but isn\'t recording.'**
  String get stillNotRecording;

  /// No description provided for @stillRecording.
  ///
  /// In en, this message translates to:
  /// **'The camera accepted, but is still recording.'**
  String get stillRecording;

  /// No description provided for @listRefusedRecording.
  ///
  /// In en, this message translates to:
  /// **'The camera won\'t send its list while recording ({detail}).'**
  String listRefusedRecording(String detail);

  /// No description provided for @listRefused.
  ///
  /// In en, this message translates to:
  /// **'The camera sent no file list ({detail}). It does this when the card is empty.'**
  String listRefused(String detail);

  /// No description provided for @listRefusedStopped.
  ///
  /// In en, this message translates to:
  /// **'The camera sent no list, even with recording stopped.'**
  String get listRefusedStopped;

  /// No description provided for @listReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the list: {detail}'**
  String listReadFailed(String detail);

  /// No description provided for @recordingDidNotRestart.
  ///
  /// In en, this message translates to:
  /// **'Recording didn\'t restart: press the camera\'s record button.'**
  String get recordingDidNotRestart;

  /// No description provided for @recordingMaybeOff.
  ///
  /// In en, this message translates to:
  /// **'The camera may not be recording: press its record button. ({detail})'**
  String recordingMaybeOff(String detail);

  /// No description provided for @recordingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Recordings'**
  String get recordingsTitle;

  /// No description provided for @nothingToDownload.
  ///
  /// In en, this message translates to:
  /// **'Nothing to download: already saved or queued.'**
  String get nothingToDownload;

  /// No description provided for @downloadStartFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not start the download: {detail}'**
  String downloadStartFailed(String detail);

  /// No description provided for @pauseToListTitle.
  ///
  /// In en, this message translates to:
  /// **'Pause recording?'**
  String get pauseToListTitle;

  /// No description provided for @pauseToListBody.
  ///
  /// In en, this message translates to:
  /// **'Recording stops for a few seconds while the list is read, then restarts. The current clip becomes downloadable too.'**
  String get pauseToListBody;

  /// No description provided for @pauseToListAction.
  ///
  /// In en, this message translates to:
  /// **'Pause and read'**
  String get pauseToListAction;

  /// No description provided for @pauseToListDone.
  ///
  /// In en, this message translates to:
  /// **'List read. Recording again.'**
  String get pauseToListDone;

  /// No description provided for @pauseToList.
  ///
  /// In en, this message translates to:
  /// **'Pause recording to read the list'**
  String get pauseToList;

  /// No description provided for @deleteWhileDownloading.
  ///
  /// In en, this message translates to:
  /// **'Some of these are downloading. Cancel or wait first.'**
  String get deleteWhileDownloading;

  /// No description provided for @deleteFromCameraTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete 1 file from the camera?} other{Delete {count} files from the camera?}}'**
  String deleteFromCameraTitle(int count);

  /// No description provided for @cannotUndo.
  ///
  /// In en, this message translates to:
  /// **'This can\'t be undone.'**
  String get cannotUndo;

  /// No description provided for @allSavedOnPhone.
  ///
  /// In en, this message translates to:
  /// **'All are saved on this phone; those copies stay.'**
  String get allSavedOnPhone;

  /// No description provided for @noneSavedOnPhone.
  ///
  /// In en, this message translates to:
  /// **'None are saved on this phone.'**
  String get noneSavedOnPhone;

  /// No description provided for @someNotSavedOnPhone.
  ///
  /// In en, this message translates to:
  /// **'{count} aren\'t saved on this phone.'**
  String someNotSavedOnPhone(int count);

  /// No description provided for @deletedFromCamera.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Deleted 1 file from the camera.} other{Deleted {count} files from the camera.}}'**
  String deletedFromCamera(int count);

  /// No description provided for @deletedSomeFromCamera.
  ///
  /// In en, this message translates to:
  /// **'Deleted {done} of {total}. The camera refused the next: {detail}'**
  String deletedSomeFromCamera(int done, int total, String detail);

  /// No description provided for @cancelSelection.
  ///
  /// In en, this message translates to:
  /// **'Cancel selection'**
  String get cancelSelection;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select all'**
  String get selectAll;

  /// No description provided for @deleteSelectedFromCamera.
  ///
  /// In en, this message translates to:
  /// **'Delete selected from camera'**
  String get deleteSelectedFromCamera;

  /// No description provided for @downloadSelected.
  ///
  /// In en, this message translates to:
  /// **'Download selected'**
  String get downloadSelected;

  /// No description provided for @selectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} selected'**
  String selectedCount(int count);

  /// No description provided for @selectSeveral.
  ///
  /// In en, this message translates to:
  /// **'Select several'**
  String get selectSeveral;

  /// Filter: show both cameras.
  ///
  /// In en, this message translates to:
  /// **'Front + rear'**
  String get frontAndRear;

  /// No description provided for @noMatch.
  ///
  /// In en, this message translates to:
  /// **'No recording matches \"{query}\".'**
  String noMatch(String query);

  /// No description provided for @readingCard.
  ///
  /// In en, this message translates to:
  /// **'Reading the card…'**
  String get readingCard;

  /// No description provided for @noRecordings.
  ///
  /// In en, this message translates to:
  /// **'No recordings on the card.'**
  String get noRecordings;

  /// No description provided for @connectToSeeRecordings.
  ///
  /// In en, this message translates to:
  /// **'Connect to the camera to see its recordings.'**
  String get connectToSeeRecordings;

  /// No description provided for @deleteFromCamera.
  ///
  /// In en, this message translates to:
  /// **'Delete from camera'**
  String get deleteFromCamera;

  /// No description provided for @recordingNow.
  ///
  /// In en, this message translates to:
  /// **'Recording now. Available when this clip ends.'**
  String get recordingNow;

  /// No description provided for @clockWasWrongAtStart.
  ///
  /// In en, this message translates to:
  /// **'The clock was wrong when this started: its file name says {time}.'**
  String clockWasWrongAtStart(String time);

  /// A clip: which camera and its size, e.g. "Front · 68 MB".
  ///
  /// In en, this message translates to:
  /// **'{lens} · {size}'**
  String chipSize(String lens, String size);

  /// No description provided for @chipDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get chipDownload;

  /// No description provided for @chipStillRecording.
  ///
  /// In en, this message translates to:
  /// **'Still recording'**
  String get chipStillRecording;

  /// No description provided for @chipQueued.
  ///
  /// In en, this message translates to:
  /// **'{lens} · queued'**
  String chipQueued(String lens);

  /// No description provided for @chipDownloading.
  ///
  /// In en, this message translates to:
  /// **'{lens} · {percent}%'**
  String chipDownloading(String lens, int percent);

  /// No description provided for @chipDownloadingStart.
  ///
  /// In en, this message translates to:
  /// **'{lens} · starting'**
  String chipDownloadingStart(String lens);

  /// No description provided for @chipRetrying.
  ///
  /// In en, this message translates to:
  /// **'{lens} · retrying {percent}%'**
  String chipRetrying(String lens, int percent);

  /// No description provided for @chipRetryingStart.
  ///
  /// In en, this message translates to:
  /// **'{lens} · retrying'**
  String chipRetryingStart(String lens);

  /// No description provided for @chipFailed.
  ///
  /// In en, this message translates to:
  /// **'{lens} · failed, tap to resume'**
  String chipFailed(String lens);

  /// No description provided for @chipSaved.
  ///
  /// In en, this message translates to:
  /// **'{lens} · saved'**
  String chipSaved(String lens);

  /// No description provided for @tapToCancel.
  ///
  /// In en, this message translates to:
  /// **'Tap to cancel'**
  String get tapToCancel;

  /// No description provided for @downloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download failed'**
  String get downloadFailed;

  /// No description provided for @queueRetrying.
  ///
  /// In en, this message translates to:
  /// **'Connection problem, retrying: {detail}'**
  String queueRetrying(String detail);

  /// Download speed, e.g. "1.3 MB/s".
  ///
  /// In en, this message translates to:
  /// **'{size}/s'**
  String perSecond(String size);

  /// No description provided for @timeLeft.
  ///
  /// In en, this message translates to:
  /// **'{span} left'**
  String timeLeft(String span);

  /// No description provided for @queueDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading {position} of {total} · {name}'**
  String queueDownloading(int position, int total, String name);

  /// No description provided for @cancelAll.
  ///
  /// In en, this message translates to:
  /// **'Cancel all'**
  String get cancelAll;

  /// No description provided for @oneDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'1 download failed: {detail}'**
  String oneDownloadFailed(String detail);

  /// No description provided for @downloadsFailed.
  ///
  /// In en, this message translates to:
  /// **'{count} downloads failed'**
  String downloadsFailed(int count);

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @dismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// No description provided for @fastTitle.
  ///
  /// In en, this message translates to:
  /// **'Fast download'**
  String get fastTitle;

  /// No description provided for @fastHint.
  ///
  /// In en, this message translates to:
  /// **'Pauses recording while downloading. About 2× faster.'**
  String get fastHint;

  /// No description provided for @fastConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Pause recording to download faster?'**
  String get fastConfirmTitle;

  /// No description provided for @fastConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Nothing is recorded while files download. Recording restarts when the queue ends or is cancelled, or when the app next reconnects.\n\nOnly use this while parked.'**
  String get fastConfirmBody;

  /// No description provided for @turnOn.
  ///
  /// In en, this message translates to:
  /// **'Turn on'**
  String get turnOn;

  /// No description provided for @fastPausing.
  ///
  /// In en, this message translates to:
  /// **'Pausing recording for fast download…'**
  String get fastPausing;

  /// No description provided for @fastPausedDownloading.
  ///
  /// In en, this message translates to:
  /// **'Recording PAUSED while files download. It restarts when they finish.'**
  String get fastPausedDownloading;

  /// No description provided for @fastPausedIdle.
  ///
  /// In en, this message translates to:
  /// **'Recording PAUSED. It wasn\'t restarted after the last fast download.'**
  String get fastPausedIdle;

  /// No description provided for @fastResuming.
  ///
  /// In en, this message translates to:
  /// **'Restarting recording…'**
  String get fastResuming;

  /// No description provided for @fastFailed.
  ///
  /// In en, this message translates to:
  /// **'Recording is still OFF: the app couldn\'t restart it.'**
  String get fastFailed;

  /// No description provided for @fastFailedDetail.
  ///
  /// In en, this message translates to:
  /// **'Recording is still OFF ({detail}). Reconnect and try again, or press the camera\'s record button.'**
  String fastFailedDetail(String detail);

  /// No description provided for @restartRecording.
  ///
  /// In en, this message translates to:
  /// **'Restart recording'**
  String get restartRecording;

  /// No description provided for @savedTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved on this phone'**
  String get savedTitle;

  /// No description provided for @deleteFromPhoneTitle.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{Delete 1 file from this phone?} other{Delete {count} files from this phone?}}'**
  String deleteFromPhoneTitle(int count);

  /// No description provided for @deleteFromPhoneBody.
  ///
  /// In en, this message translates to:
  /// **'Only the phone\'s copy is removed; the camera\'s stays.'**
  String get deleteFromPhoneBody;

  /// No description provided for @deletedFromPhone.
  ///
  /// In en, this message translates to:
  /// **'Deleted from this phone.'**
  String get deletedFromPhone;

  /// No description provided for @deletedSomeFromPhone.
  ///
  /// In en, this message translates to:
  /// **'Deleted {done} of {total}. The rest couldn\'t be removed.'**
  String deletedSomeFromPhone(int done, int total);

  /// No description provided for @lookingForSaved.
  ///
  /// In en, this message translates to:
  /// **'Looking for saved clips…'**
  String get lookingForSaved;

  /// No description provided for @nothingSaved.
  ///
  /// In en, this message translates to:
  /// **'Nothing saved yet. Downloaded recordings appear here and in your gallery (Movies/nCAM).'**
  String get nothingSaved;

  /// No description provided for @noSavedMatch.
  ///
  /// In en, this message translates to:
  /// **'No saved recording matches \"{query}\".\nTry a name, a date such as \"17 Nov\" or a time such as \"19:22\".'**
  String noSavedMatch(String query);

  /// No description provided for @nameRecording.
  ///
  /// In en, this message translates to:
  /// **'Name recording'**
  String get nameRecording;

  /// No description provided for @renameRecording.
  ///
  /// In en, this message translates to:
  /// **'Rename recording'**
  String get renameRecording;

  /// No description provided for @nameLabel.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameLabel;

  /// No description provided for @nameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Near miss on the A1'**
  String get nameHint;

  /// No description provided for @removeName.
  ///
  /// In en, this message translates to:
  /// **'Remove name'**
  String get removeName;

  /// No description provided for @nameMenu.
  ///
  /// In en, this message translates to:
  /// **'Name…'**
  String get nameMenu;

  /// No description provided for @renameMenu.
  ///
  /// In en, this message translates to:
  /// **'Rename…'**
  String get renameMenu;

  /// No description provided for @deleteFromPhone.
  ///
  /// In en, this message translates to:
  /// **'Delete from this phone'**
  String get deleteFromPhone;

  /// No description provided for @clipNotSaved.
  ///
  /// In en, this message translates to:
  /// **'This clip isn\'t on the phone, and the camera isn\'t connected to play it from.'**
  String get clipNotSaved;

  /// No description provided for @clipPlayFailed.
  ///
  /// In en, this message translates to:
  /// **'This clip could not be played: {detail}'**
  String clipPlayFailed(String detail);

  /// No description provided for @playbackSpeed.
  ///
  /// In en, this message translates to:
  /// **'Playback speed'**
  String get playbackSpeed;

  /// The usual speed, 1×.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get speedNormal;

  /// A playback speed, e.g. "1.5×".
  ///
  /// In en, this message translates to:
  /// **'{speed}×'**
  String speedValue(String speed);

  /// No description provided for @streamingFromCamera.
  ///
  /// In en, this message translates to:
  /// **'Playing from the camera'**
  String get streamingFromCamera;

  /// No description provided for @playFromCamera.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get playFromCamera;

  /// Over the live picture; {reasons} is one or more of the liveReason texts.
  ///
  /// In en, this message translates to:
  /// **'Live view limited: {reasons}'**
  String liveLimited(String reasons);

  /// No description provided for @liveReasonDownloading.
  ///
  /// In en, this message translates to:
  /// **'a clip is downloading'**
  String get liveReasonDownloading;

  /// No description provided for @liveReasonWeakSignal.
  ///
  /// In en, this message translates to:
  /// **'weak Wi-Fi ({dbm} dBm)'**
  String liveReasonWeakSignal(int dbm);

  /// No description provided for @liveReasonSlowLink.
  ///
  /// In en, this message translates to:
  /// **'slow connection'**
  String get liveReasonSlowLink;

  /// Shown briefly when the whole picture shows again, as large as it fits.
  ///
  /// In en, this message translates to:
  /// **'Best fit'**
  String get zoomFit;

  /// Shown briefly after pinching out so the picture fills the screen.
  ///
  /// In en, this message translates to:
  /// **'Zoomed to fill'**
  String get zoomFill;

  /// Shown briefly while zoomed in, e.g. "2.5×".
  ///
  /// In en, this message translates to:
  /// **'{factor}×'**
  String zoomFactor(String factor);

  /// Fit button: fill the screen, cutting the edges off.
  ///
  /// In en, this message translates to:
  /// **'Zoom to fill'**
  String get zoomToFill;

  /// Fit button: back to the whole picture, as large as it fits.
  ///
  /// In en, this message translates to:
  /// **'Best fit'**
  String get zoomToFit;

  /// No description provided for @liveTitle.
  ///
  /// In en, this message translates to:
  /// **'Live view'**
  String get liveTitle;

  /// Pictures per second.
  ///
  /// In en, this message translates to:
  /// **'{fps} fps'**
  String fps(int fps);

  /// No description provided for @liveStarting.
  ///
  /// In en, this message translates to:
  /// **'Starting live view…'**
  String get liveStarting;

  /// No description provided for @liveStoppedShort.
  ///
  /// In en, this message translates to:
  /// **'Live view stopped.'**
  String get liveStoppedShort;

  /// No description provided for @liveStopped.
  ///
  /// In en, this message translates to:
  /// **'Live view stopped: {detail}'**
  String liveStopped(String detail);

  /// Why live view stopped; follows "Live view stopped: ".
  ///
  /// In en, this message translates to:
  /// **'the camera closed the stream'**
  String get liveStreamClosed;

  /// No description provided for @liveConnectionLost.
  ///
  /// In en, this message translates to:
  /// **'Connection lost. Reconnecting…'**
  String get liveConnectionLost;

  /// No description provided for @liveRestarting.
  ///
  /// In en, this message translates to:
  /// **'Restarting the connection…'**
  String get liveRestarting;

  /// No description provided for @liveReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get liveReconnecting;

  /// No description provided for @liveNoPicture.
  ///
  /// In en, this message translates to:
  /// **'The camera isn\'t sending a picture.'**
  String get liveNoPicture;

  /// A camera view without a known name.
  ///
  /// In en, this message translates to:
  /// **'View {number}'**
  String viewNumber(int number);

  /// No description provided for @viewSwitchFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not switch view: {detail}'**
  String viewSwitchFailed(String detail);

  /// No description provided for @pipTooltip.
  ///
  /// In en, this message translates to:
  /// **'Picture-in-picture'**
  String get pipTooltip;

  /// No description provided for @pipUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Picture-in-picture isn\'t available. Allow it for nCAM in Android settings.'**
  String get pipUnavailable;

  /// No description provided for @logReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the log: {detail}'**
  String logReadFailed(String detail);

  /// No description provided for @reload.
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get reload;

  /// No description provided for @saveToDownloads.
  ///
  /// In en, this message translates to:
  /// **'Save to Downloads'**
  String get saveToDownloads;

  /// No description provided for @logSaved.
  ///
  /// In en, this message translates to:
  /// **'Saved to Downloads as {name}'**
  String logSaved(String name);

  /// No description provided for @logSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save the log: {detail}'**
  String logSaveFailed(String detail);

  /// No description provided for @copyAll.
  ///
  /// In en, this message translates to:
  /// **'Copy all'**
  String get copyAll;

  /// No description provided for @logCopied.
  ///
  /// In en, this message translates to:
  /// **'Log copied.'**
  String get logCopied;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @logEmpty.
  ///
  /// In en, this message translates to:
  /// **'Nothing logged yet.'**
  String get logEmpty;

  /// No description provided for @sectionApp.
  ///
  /// In en, this message translates to:
  /// **'App'**
  String get sectionApp;

  /// No description provided for @sectionCamera.
  ///
  /// In en, this message translates to:
  /// **'Camera'**
  String get sectionCamera;

  /// No description provided for @sectionWifi.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi'**
  String get sectionWifi;

  /// No description provided for @sectionStorage.
  ///
  /// In en, this message translates to:
  /// **'Storage'**
  String get sectionStorage;

  /// No description provided for @sectionDevice.
  ///
  /// In en, this message translates to:
  /// **'Device'**
  String get sectionDevice;

  /// No description provided for @colours.
  ///
  /// In en, this message translates to:
  /// **'Colours'**
  String get colours;

  /// No description provided for @appearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get appearance;

  /// Colours taken from the phone's wallpaper.
  ///
  /// In en, this message translates to:
  /// **'Wallpaper'**
  String get colorWallpaper;

  /// No description provided for @colorBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get colorBlue;

  /// No description provided for @colorTeal.
  ///
  /// In en, this message translates to:
  /// **'Teal'**
  String get colorTeal;

  /// No description provided for @colorGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get colorGreen;

  /// No description provided for @colorOrange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get colorOrange;

  /// No description provided for @colorRed.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get colorRed;

  /// No description provided for @colorPurple.
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get colorPurple;

  /// No description provided for @modeSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get modeSystem;

  /// No description provided for @modeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get modeLight;

  /// No description provided for @modeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get modeDark;

  /// Dark mode with true black backgrounds.
  ///
  /// In en, this message translates to:
  /// **'Pure black'**
  String get modeBlack;

  /// No description provided for @wallpaperNote.
  ///
  /// In en, this message translates to:
  /// **'Wallpaper colours need Android 12 or later; otherwise blue is used.'**
  String get wallpaperNote;

  /// No description provided for @cameraIsRecording.
  ///
  /// In en, this message translates to:
  /// **'The camera is recording'**
  String get cameraIsRecording;

  /// No description provided for @cameraIsRecordingHint.
  ///
  /// In en, this message translates to:
  /// **'If a change stops it, the app restarts recording.'**
  String get cameraIsRecordingHint;

  /// No description provided for @autoConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect on start-up'**
  String get autoConnect;

  /// No description provided for @autoConnectHint.
  ///
  /// In en, this message translates to:
  /// **'Join the saved camera when the app opens.'**
  String get autoConnectHint;

  /// No description provided for @syncOnConnect.
  ///
  /// In en, this message translates to:
  /// **'Sync time on connect'**
  String get syncOnConnect;

  /// No description provided for @syncOnConnectHint.
  ///
  /// In en, this message translates to:
  /// **'Set the camera clock to the phone\'s.'**
  String get syncOnConnectHint;

  /// No description provided for @autoPip.
  ///
  /// In en, this message translates to:
  /// **'Auto picture-in-picture'**
  String get autoPip;

  /// No description provided for @autoPipHint.
  ///
  /// In en, this message translates to:
  /// **'Float video when you leave the app.'**
  String get autoPipHint;

  /// No description provided for @sectionBackground.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get sectionBackground;

  /// No description provided for @watchTitle.
  ///
  /// In en, this message translates to:
  /// **'Background clock sync'**
  String get watchTitle;

  /// No description provided for @watchHint.
  ///
  /// In en, this message translates to:
  /// **'Sets the camera clock whenever it starts.'**
  String get watchHint;

  /// No description provided for @watchNeedsCamera.
  ///
  /// In en, this message translates to:
  /// **'Connect to the camera first.'**
  String get watchNeedsCamera;

  /// No description provided for @watchNewClip.
  ///
  /// In en, this message translates to:
  /// **'New clip after sync'**
  String get watchNewClip;

  /// No description provided for @watchNewClipHint.
  ///
  /// In en, this message translates to:
  /// **'Cuts the wrongly dated clip short (2 s gap).'**
  String get watchNewClipHint;

  /// No description provided for @watchBattery.
  ///
  /// In en, this message translates to:
  /// **'No battery limits'**
  String get watchBattery;

  /// Once allowed: the watchBatteryHint text, marked as allowed.
  ///
  /// In en, this message translates to:
  /// **'{hint} (Allowed)'**
  String watchBatteryOk(String hint);

  /// No description provided for @watchBatteryHint.
  ///
  /// In en, this message translates to:
  /// **'Keeps Android from stopping the sync.'**
  String get watchBatteryHint;

  /// No description provided for @watchHideNotification.
  ///
  /// In en, this message translates to:
  /// **'Hide notification'**
  String get watchHideNotification;

  /// No description provided for @watchHideNotificationHint.
  ///
  /// In en, this message translates to:
  /// **'The sync keeps running.'**
  String get watchHideNotificationHint;

  /// No description provided for @recordButton.
  ///
  /// In en, this message translates to:
  /// **'Record button'**
  String get recordButton;

  /// No description provided for @recordButtonHint.
  ///
  /// In en, this message translates to:
  /// **'Side of the dock'**
  String get recordButtonHint;

  /// No description provided for @sideLeft.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get sideLeft;

  /// No description provided for @sideRight.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get sideRight;

  /// No description provided for @connectToChangeSettings.
  ///
  /// In en, this message translates to:
  /// **'Connect on the home page to change camera settings.'**
  String get connectToChangeSettings;

  /// No description provided for @readingSettings.
  ///
  /// In en, this message translates to:
  /// **'Reading settings…'**
  String get readingSettings;

  /// No description provided for @settingsReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read the settings'**
  String get settingsReadFailed;

  /// No description provided for @otherValues.
  ///
  /// In en, this message translates to:
  /// **'Other values (read-only)'**
  String get otherValues;

  /// No description provided for @otherValuesHint.
  ///
  /// In en, this message translates to:
  /// **'Reported by the camera with no choices.'**
  String get otherValuesHint;

  /// A camera setting without a known name.
  ///
  /// In en, this message translates to:
  /// **'Setting {id}'**
  String settingNumber(int id);

  /// No description provided for @fixedOnCamera.
  ///
  /// In en, this message translates to:
  /// **'Fixed on this camera'**
  String get fixedOnCamera;

  /// No description provided for @changingSetting.
  ///
  /// In en, this message translates to:
  /// **'Changing setting…'**
  String get changingSetting;

  /// No description provided for @changeWifi.
  ///
  /// In en, this message translates to:
  /// **'Change Wi-Fi name and password'**
  String get changeWifi;

  /// No description provided for @changeWifiHint.
  ///
  /// In en, this message translates to:
  /// **'The camera restarts its Wi-Fi; the app reconnects.'**
  String get changeWifiHint;

  /// No description provided for @changingWifi.
  ///
  /// In en, this message translates to:
  /// **'Changing the camera\'s Wi-Fi…'**
  String get changingWifi;

  /// No description provided for @wifiChanged.
  ///
  /// In en, this message translates to:
  /// **'Connected to \"{name}\" with the new password.'**
  String wifiChanged(String name);

  /// No description provided for @sdCard.
  ///
  /// In en, this message translates to:
  /// **'SD card'**
  String get sdCard;

  /// No description provided for @formatSdCard.
  ///
  /// In en, this message translates to:
  /// **'Format SD card'**
  String get formatSdCard;

  /// No description provided for @formatSdCardHint.
  ///
  /// In en, this message translates to:
  /// **'Erases every recording on the camera.'**
  String get formatSdCardHint;

  /// No description provided for @formatTitle.
  ///
  /// In en, this message translates to:
  /// **'Format the SD card?'**
  String get formatTitle;

  /// No description provided for @formatBody.
  ///
  /// In en, this message translates to:
  /// **'Erases every recording on the camera; this can\'t be undone. Clips saved on this phone are kept. Recording pauses, then restarts.'**
  String get formatBody;

  /// No description provided for @formatAction.
  ///
  /// In en, this message translates to:
  /// **'Erase everything'**
  String get formatAction;

  /// No description provided for @formatting.
  ///
  /// In en, this message translates to:
  /// **'Formatting the card…'**
  String get formatting;

  /// No description provided for @restoreFactory.
  ///
  /// In en, this message translates to:
  /// **'Restore factory settings'**
  String get restoreFactory;

  /// No description provided for @resetTitle.
  ///
  /// In en, this message translates to:
  /// **'Restore factory settings?'**
  String get resetTitle;

  /// No description provided for @resetBody.
  ///
  /// In en, this message translates to:
  /// **'Camera settings return to their defaults. If the Wi-Fi name and password reset too, reconnect with the defaults.'**
  String get resetBody;

  /// No description provided for @resetAction.
  ///
  /// In en, this message translates to:
  /// **'Reset camera'**
  String get resetAction;

  /// No description provided for @resetting.
  ///
  /// In en, this message translates to:
  /// **'Resetting the camera…'**
  String get resetting;

  /// No description provided for @wifiDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Camera Wi-Fi'**
  String get wifiDialogTitle;

  /// No description provided for @wifiName.
  ///
  /// In en, this message translates to:
  /// **'Wi-Fi name'**
  String get wifiName;

  /// No description provided for @newPassword.
  ///
  /// In en, this message translates to:
  /// **'New password'**
  String get newPassword;

  /// No description provided for @wifiNameRule.
  ///
  /// In en, this message translates to:
  /// **'Name: 1–32 letters, digits or symbols, no spaces.'**
  String get wifiNameRule;

  /// No description provided for @wifiPasswordRule.
  ///
  /// In en, this message translates to:
  /// **'Password: 8–63 letters, digits or symbols, no spaces.'**
  String get wifiPasswordRule;

  /// No description provided for @wifiPasswordWarning.
  ///
  /// In en, this message translates to:
  /// **'Write it down: if it\'s lost, only the camera\'s reset button gets you back in.'**
  String get wifiPasswordWarning;

  /// No description provided for @change.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// No description provided for @settingPhotoSize.
  ///
  /// In en, this message translates to:
  /// **'Photo size'**
  String get settingPhotoSize;

  /// No description provided for @settingVideoResolution.
  ///
  /// In en, this message translates to:
  /// **'Video resolution'**
  String get settingVideoResolution;

  /// No description provided for @settingExposure.
  ///
  /// In en, this message translates to:
  /// **'Exposure'**
  String get settingExposure;

  /// No description provided for @settingRecordAudio.
  ///
  /// In en, this message translates to:
  /// **'Record audio'**
  String get settingRecordAudio;

  /// No description provided for @settingAutoPowerOff.
  ///
  /// In en, this message translates to:
  /// **'Auto power off'**
  String get settingAutoPowerOff;

  /// No description provided for @settingLoopRecording.
  ///
  /// In en, this message translates to:
  /// **'Loop recording'**
  String get settingLoopRecording;

  /// No description provided for @settingGSensor.
  ///
  /// In en, this message translates to:
  /// **'G-sensor'**
  String get settingGSensor;

  /// No description provided for @settingDateStamp.
  ///
  /// In en, this message translates to:
  /// **'Date stamp'**
  String get settingDateStamp;

  /// Wide dynamic range.
  ///
  /// In en, this message translates to:
  /// **'WDR'**
  String get settingWdr;

  /// No description provided for @settingMotionDetection.
  ///
  /// In en, this message translates to:
  /// **'Motion detection'**
  String get settingMotionDetection;

  /// No description provided for @settingAutoRecording.
  ///
  /// In en, this message translates to:
  /// **'Auto recording'**
  String get settingAutoRecording;

  /// The camera's own menu language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingLanguage;

  /// No description provided for @settingTvMode.
  ///
  /// In en, this message translates to:
  /// **'TV mode'**
  String get settingTvMode;

  /// A setting choice in minutes.
  ///
  /// In en, this message translates to:
  /// **'{count} min'**
  String optionMinutes(int count);

  /// No description provided for @optionOn.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get optionOn;

  /// No description provided for @optionOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get optionOff;

  /// No description provided for @recordingRestarted.
  ///
  /// In en, this message translates to:
  /// **'Recording stopped for this and was restarted.'**
  String get recordingRestarted;

  /// No description provided for @recordingNotRestarted.
  ///
  /// In en, this message translates to:
  /// **'Recording stopped and did NOT restart. Press the camera\'s record button.'**
  String get recordingNotRestarted;

  /// No description provided for @changeRefusedRecording.
  ///
  /// In en, this message translates to:
  /// **'The camera refused the change ({detail}). It may only accept it when not recording.'**
  String changeRefusedRecording(String detail);

  /// No description provided for @changeRefused.
  ///
  /// In en, this message translates to:
  /// **'The camera refused the change ({detail}).'**
  String changeRefused(String detail);

  /// No description provided for @cameraUnreachable.
  ///
  /// In en, this message translates to:
  /// **'Could not reach the camera: {detail}'**
  String cameraUnreachable(String detail);

  /// No description provided for @formatRefused.
  ///
  /// In en, this message translates to:
  /// **'The camera refused to format the card ({detail}).'**
  String formatRefused(String detail);

  /// No description provided for @formatDone.
  ///
  /// In en, this message translates to:
  /// **'The card was formatted.'**
  String get formatDone;

  /// No description provided for @recordingRestartedShort.
  ///
  /// In en, this message translates to:
  /// **'Recording restarted.'**
  String get recordingRestartedShort;

  /// No description provided for @formatFailed.
  ///
  /// In en, this message translates to:
  /// **'Formatting went wrong: {detail}. Check that the camera is recording.'**
  String formatFailed(String detail);

  /// No description provided for @resetDone.
  ///
  /// In en, this message translates to:
  /// **'Factory settings restored. If the camera\'s Wi-Fi reset too, enter the defaults on the home page.'**
  String get resetDone;

  /// No description provided for @resetRefused.
  ///
  /// In en, this message translates to:
  /// **'The camera refused the reset ({detail}).'**
  String resetRefused(String detail);

  /// No description provided for @resetUnconfirmed.
  ///
  /// In en, this message translates to:
  /// **'Reset sent, but the camera didn\'t confirm: {detail}'**
  String resetUnconfirmed(String detail);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
