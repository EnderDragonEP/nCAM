import 'models.dart';

/// One moment of recording: the front clip, the rear clip, or both.
class Recording {
  Recording({this.front, this.rear, this.other, required this.beingWritten});

  final CameraFile? front;
  final CameraFile? rear;

  /// A file that is not a recognisable front/rear clip (kept so nothing is hidden).
  final CameraFile? other;

  /// The camera is still writing this recording.
  final bool beingWritten;

  List<CameraFile> get files => [?front, ?rear, ?other];

  String get id => files.first.path;

  int get size => files.fold(0, (sum, f) => sum + f.size);

  /// Start time according to the file name.
  DateTime? get start => (front ?? rear ?? other)?.startTime;

  /// Last time the camera wrote to the recording.
  DateTime? get end {
    DateTime? latest;
    for (final f in files) {
      final t = f.writeTime;
      if (t != null && (latest == null || t.isAfter(latest))) latest = t;
    }
    return latest;
  }

  /// True when the date in the file name cannot be right: the camera's clock was wrong
  /// when the clip started and was corrected while it was being recorded.
  bool get nameDateSuspect {
    final s = start, e = end;
    if (s == null || e == null) return false;
    final length = e.difference(s);
    return length < const Duration(minutes: -1) ||
        length > const Duration(hours: 6);
  }

  /// The time to show and sort by.
  DateTime? get time => nameDateSuspect ? end : (start ?? end);

  Duration? get length {
    final s = start, e = end;
    if (s == null || e == null || nameDateSuspect) return null;
    final d = e.difference(s);
    return d.isNegative ? null : d;
  }
}

/// Groups the camera's flat file list into recordings, newest first.
///
/// The camera writes a front clip `…_nnnA` and a rear clip `…_(nnn+1)B` for the same
/// moment. Their name timestamps are normally identical but can differ by a second.
List<Recording> groupRecordings(
  List<CameraFile> files, {
  Set<String> writing = const {},
}) {
  final sorted = [...files]..sort((a, b) => a.name.compareTo(b.name));
  final result = <Recording>[];
  for (var i = 0; i < sorted.length; i++) {
    final f = sorted[i];
    final next = i + 1 < sorted.length ? sorted[i + 1] : null;
    if (f.lens == Lens.front && next != null && _isPair(f, next)) {
      result.add(
        Recording(
          front: f,
          rear: next,
          beingWritten: writing.contains(f.path) || writing.contains(next.path),
        ),
      );
      i++;
      continue;
    }
    final written = writing.contains(f.path);
    result.add(switch (f.lens) {
      Lens.front when f.isVideo => Recording(front: f, beingWritten: written),
      Lens.rear when f.isVideo => Recording(rear: f, beingWritten: written),
      _ => Recording(other: f, beingWritten: written),
    });
  }
  result.sort((a, b) {
    final ta = a.time, tb = b.time;
    if (ta == null && tb == null) return b.id.compareTo(a.id);
    if (ta == null) return 1;
    if (tb == null) return -1;
    final c = tb.compareTo(ta);
    return c != 0 ? c : b.id.compareTo(a.id);
  });
  return result;
}

bool _isPair(CameraFile front, CameraFile rear) {
  if (rear.lens != Lens.rear || !front.isVideo || !rear.isVideo) return false;
  final fs = front.sequence, rs = rear.sequence;
  final ft = front.startTime, rt = rear.startTime;
  if (fs == null || rs == null || ft == null || rt == null) return false;
  return rs == fs + 1 && rt.difference(ft).abs() <= const Duration(seconds: 5);
}
