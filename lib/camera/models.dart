/// Which lens recorded a clip. The camera names front clips `…A.TS` and rear clips `…B.TS`.
enum Lens { front, rear, unknown }

class CameraFile {
  CameraFile({
    required this.name,
    required this.path,
    required this.size,
    required this.writeTime,
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
  bool get isRecording => recordingSeconds > 0;
}

class CameraProtocolException implements Exception {
  const CameraProtocolException(this.message);
  final String message;

  @override
  String toString() => 'CameraProtocolException: $message';
}
