import 'package:flutter/widgets.dart';

import 'app_localizations.dart';

export 'app_localizations.dart';

/// A text for the user, put into their language when it is shown. The app's state
/// lives apart from the screens, so it hands these over instead of finished strings.
typedef Msg = String Function(AppLocalizations l);

/// The texts in English, the language they are written in first (lib/l10n/app_en.arb).
final AppLocalizations english = lookupAppLocalizations(const Locale('en'));

extension L10nContext on BuildContext {
  /// The app's texts in the user's language; English where the app's translations are
  /// not set up, as in some tests.
  AppLocalizations get l10n => AppLocalizations.of(this) ?? english;
}
