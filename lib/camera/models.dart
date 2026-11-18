/// Which lens recorded a clip. The camera names front clips `…A.TS` and rear clips `…B.TS`.
enum Lens { front, rear, unknown }

class CameraFile {
  CameraFile({
    required this.name,
    required this.path,
    required this.size,
    required this.writeTime,
    this.sizeSlack = 0,
  }) {
    final m = _namePattern.firstMatch(name);
    if (m == null) {
      startTime = null;
      sequence = null;
      lens = Lens.unknown;
    } else {
      int g(int i) => int.parse(m.group(i)!);
      startTime = DateTime(g(1), g(2), g(3), g(4), g(5), g(6));
      sequence = g(7);
      lens = switch (m.group(8)) {
        'A' => Lens.front,
        'B' => Lens.rear,
        _ => Lens.unknown,
      };
    }
  }

  // 2026_1111_192257_045A.TS
  static final _namePattern = RegExp(
    r'^(\d{4})_(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})_(\d+)([A-Za-z])\.',
  );

  final String name;

  /// URL path on the camera, e.g. `/Novatek/Movie/2026_1111_192257_045A.TS`.
  final String path;
  final int size;

  /// How far the real size may be from [size]: 0 from the camera's file list, more from
  /// its folder web page, which rounds sizes ("231.33 MB").
  final int sizeSlack;

  /// Whether a file of [bytes] can be this one.
  bool sizeMatches(int bytes) => (bytes - size).abs() <= sizeSlack;

  /// The camera's last-write time for the file (its `TIME` field). For the clip being
  /// recorded this is close to the camera's current clock.
  final DateTime? writeTime;

  /// When recording of this clip started, taken from the file name.
  late final DateTime? startTime;
  late final int? sequence;
  late final Lens lens;

  bool get isVideo {
    final n = name.toLowerCase();
    return n.endsWith('.ts') || n.endsWith('.mp4') || n.endsWith('.mov');
  }

  bool get isPhoto {
    final n = name.toLowerCase();
    return n.endsWith('.jpg') || n.endsWith('.jpeg');
  }

  /// Videos and photos. The camera also lists its own log files, which are not
  /// recordings.
  bool get isMedia => isVideo || isPhoto;

  /// Best guess at when the clip was recorded.
  DateTime? get time => startTime ?? writeTime;
}

class CameraStatus {
  const CameraStatus({
    required this.firmware,
    required this.cardStatus,
    required this.freeBytes,
    required this.recordingSeconds,
  });

  final String firmware;

  /// Raw value of command 3024. 0 = no card.
  final int cardStatus;
  final int freeBytes;

  /// Elapsed seconds of the current recording; 0 when not recording.
  final int recordingSeconds;

  bool get hasCard => cardStatus != 0;

  CameraStatus withRecordingSeconds(int seconds) => CameraStatus(
    firmware: firmware,
    cardStatus: cardStatus,
    freeBytes: freeBytes,
    recordingSeconds: seconds,
  );
  bool get isRecording => recordingSeconds > 0;
}

class SettingOption {
  const SettingOption(this.index, this.label);

  /// The value the camera expects for this choice.
  final int index;

  /// The camera's own label, e.g. `ON`, `3MIN`, `1920x1080P30_1920x1080P30`.
  final String label;
}

/// A setting the camera says it supports, with its choices and current value.
class CameraSetting {
  const CameraSetting({
    required this.cmd,
    required this.name,
    required this.options,
    this.value,
  });

  /// Command id used to change it.
  final int cmd;

  /// The camera's own name, e.g. `MOVIE_AUDIO`.
  final String name;
  final List<SettingOption> options;

  /// Index of the current choice, or null if the camera did not report one.
  final int? value;

  /// With a single choice there is nothing to change.
  bool get changeable => options.length > 1;

  SettingOption? get current {
    for (final o in options) {
      if (o.index == value) return o;
    }
    return null;
  }
}

class CameraSettings {
  const CameraSettings({required this.listed, required this.other});

  /// Settings the camera lists with choices (command 3031).
  final List<CameraSetting> listed;

  /// Values the camera reports (command 3014) without listing any choices for them,
  /// by command id. Shown read-only: nothing says what else they could be set to.
  final Map<int, String> other;
}

/// The camera answered the "list files" command with something other than a list.
class FileListUnavailable extends CameraProtocolException {
  const FileListUnavailable(super.message, {this.status});

  /// The camera's status code, when it answered with one.
  final int? status;
}

class CameraProtocolException implements Exception {
  const CameraProtocolException(this.message);
  final String message;

  @override
  String toString() => 'CameraProtocolException: $message';
}
