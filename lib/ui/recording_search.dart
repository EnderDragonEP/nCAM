import 'package:intl/intl.dart';

import '../camera/models.dart';
import '../camera/recordings.dart';
import '../l10n/l10n.dart';
import 'format.dart';

// English names, so English words find recordings in any language.
const _monthNames = [
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december',
];
const _dayNames = [
  'monday',
  'tuesday',
  'wednesday',
  'thursday',
  'friday',
  'saturday',
  'sunday',
];

/// Whether [r] matches what was typed in the search box: every word must appear in
/// its name, its date and time (written several ways: "Tue 17 Nov 2026",
/// "2026-11-17 19:22:57", "november", "17/11", "11/17"), its file names or its
/// lenses ("front", "rear"). Month, day and lens names match in the user's language
/// and in English.
bool recordingMatches(
  AppLocalizations l,
  Recording r,
  String? name,
  String query,
) {
  final words = query.toLowerCase().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return true;
  final t = r.time;
  final text = [
    ?name,
    if (t != null) ...[
      formatDay(l, t),
      formatDateTime(t),
      DateFormat('MMMM EEEE', l.localeName).format(t),
      _monthNames[t.month - 1],
      _dayNames[t.weekday - 1],
      '${t.day}/${t.month}',
      '${t.month}/${t.day}',
    ],
    for (final f in r.files) ...[
      f.name,
      ...switch (f.lens) {
        Lens.front => [l.front, 'front'],
        Lens.rear => [l.rear, 'rear'],
        Lens.unknown => const <String>[],
      },
    ],
  ].join(' ').toLowerCase();
  return words.every(text.contains);
}
