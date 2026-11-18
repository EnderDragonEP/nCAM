import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncam/l10n/l10n.dart';
import 'package:ncam/camera/fake_transport.dart';
import 'package:ncam/camera/transport.dart';
import 'package:ncam/state/credentials.dart';
import 'package:ncam/state/session.dart';

/// Phone time used in every test.
final phoneNow = DateTime(2026, 11, 11, 19, 57, 54);

ProviderContainer makeContainer(
  FakeCameraTransport fake, {
  CredentialStore? store,
}) {
  final c = ProviderContainer(
    overrides: [
      transportProvider.overrideWithValue(fake),
      credentialStoreProvider.overrideWithValue(
        store ?? MemoryCredentialStore(),
      ),
      clockProvider.overrideWithValue(() => phoneNow),
      cameraRetryDelayProvider.overrideWithValue(Duration.zero),
      clockProbeDelayProvider.overrideWithValue(Duration.zero),
    ],
  );
  addTearDown(c.dispose);
  c.listen(sessionProvider, (_, _) {});
  return c;
}

/// Lets queued async work run until the session is idle.
Future<SessionState> settle(ProviderContainer c) async {
  var idle = 0;
  for (var i = 0; i < 500; i++) {
    await Future<void>.delayed(Duration.zero);
    final s = c.read(sessionProvider);
    idle = (s.loaded && !s.busy) ? idle + 1 : 0;
    if (idle >= 5) return s;
  }
  fail('session did not settle');
}

void main() {
  test(
    'connect reads status, syncs the clock and remembers the camera',
    () async {
      // Camera clock exactly one month behind, as found on the real device.
      final fake = FakeCameraTransport()
        ..cameraClock = () => DateTime(2026, 10, 11, 19, 57, 54);
      final store = MemoryCredentialStore();
      final c = makeContainer(fake, store: store);
      await settle(c);

      await c.read(sessionProvider.notifier).connect('NoodleCam', 'secret');
      final s = await settle(c);

      expect(s.link, LinkState.connected);
      expect(s.error, isNull);
      expect(s.status!.firmware, 'DVR52AFHW3_YL_V3.19_TS');
      expect(s.status!.isRecording, isTrue);
      expect(s.status!.hasCard, isTrue);
      expect(s.files, hasLength(6));

      expect(fake.dateSet, '2026-11-11');
      expect(fake.timeSet, '19:57:54');
      expect(s.timeSync!.ok, isTrue);
      expect(s.timeSync!.cameraAheadBy, const Duration(days: -31));

      expect((await store.load())!.ssid, 'NoodleCam');
      // Recording must never be touched: no mode switch (3001) and no start/stop (2001).
      expect(fake.requests.where((u) => u.contains('cmd=3001')), isEmpty);
      expect(fake.requests.where((u) => u.contains('cmd=2001')), isEmpty);
    },
  );

  test('a correct camera clock is reported as already right', () async {
    final fake = FakeCameraTransport()..cameraClock = () => phoneNow;
    final c = makeContainer(fake);
    await settle(c);
    await c.read(sessionProvider.notifier).connect('NoodleCam', 'secret');
    final s = await settle(c);
    expect(s.timeSync!.cameraAheadBy, Duration.zero);
  });

  test('clock offset is unknown when the camera is not recording', () async {
    final fake = FakeCameraTransport(recordingSeconds: 0);
    for (final f in fake.files) {
      f.recording = false;
    }
    final c = makeContainer(fake);
    await settle(c);
    await c.read(sessionProvider.notifier).connect('NoodleCam', 'secret');
    final s = await settle(c);
    expect(s.timeSync!.ok, isTrue);
    expect(s.timeSync!.cameraAheadBy, isNull);
    expect(fake.timeSet, '19:57:54');
  });

  test('saved camera reconnects on start', () async {
    final fake = FakeCameraTransport();
    final c = makeContainer(
      fake,
      store: MemoryCredentialStore(
        const CameraCredentials('NoodleCam', 'secret'),
      ),
    );
    final s = await settle(c);
    expect(s.link, LinkState.connected);
    expect(s.timeSync, isNotNull);
  });

  test('failed join shows an error and saves nothing', () async {
    final fake = FakeCameraTransport(failConnect: true);
    final store = MemoryCredentialStore();
    final c = makeContainer(fake, store: store);
    await settle(c);
    await c.read(sessionProvider.notifier).connect('NoodleCam', 'wrong');
    final s = await settle(c);
    expect(s.link, LinkState.disconnected);
    expect(s.error!(english), contains('Could not join'));
    expect(await store.load(), isNull);
  });

  test('a rejected time command is reported, not ignored', () async {
    final fake = FakeCameraTransport()..setTimeStatus = -1;
    final c = makeContainer(fake);
    await settle(c);
    await c.read(sessionProvider.notifier).connect('NoodleCam', 'secret');
    final s = await settle(c);
    expect(s.timeSync!.ok, isFalse);
    expect(s.timeSync!.error, contains('3005'));
  });

  test('clock is synced again when the link comes back', () async {
    final fake = FakeCameraTransport();
    final c = makeContainer(fake);
    await settle(c);
    await c.read(sessionProvider.notifier).connect('NoodleCam', 'secret');
    await settle(c);
    int syncs() => fake.requests.where((u) => u.contains('cmd=3006')).length;
    expect(syncs(), 1);

    fake.dropLink();
    await settle(c);
    expect(c.read(sessionProvider).link, LinkState.lost);
    fake.restoreLink();
    await settle(c);
    expect(syncs(), 2);
  });

  test('a camera that will not list files still connects and syncs', () async {
    // Seen on the real camera: a status reply instead of a file list. With nothing on
    // the card there is no folder page either.
    final fake = FakeCameraTransport()
      ..fileListStatus = -256
      ..folderPageAvailable = false;
    final c = makeContainer(fake);
    await settle(c);
    await c.read(sessionProvider.notifier).connect('NoodleCam', 'secret');
    final s = await settle(c);

    expect(s.link, LinkState.connected);
    expect(s.error, isNull);
    expect(s.status!.firmware, 'DVR52AFHW3_YL_V3.19_TS');
    expect(s.files, isEmpty);
    expect(s.filesError!(english), contains('status -256'));
    expect(s.timeSync!.ok, isTrue);
    expect(fake.timeSet, '19:57:54');

    // Once the camera has files again the note goes away.
    fake.fileListStatus = null;
    await c.read(sessionProvider.notifier).refresh();
    final later = await settle(c);
    expect(later.filesError, isNull);
    expect(later.files, hasLength(6));
  });

  test('a list refused while recording is read from the folder page', () async {
    // The camera from 12 Nov on: status -3 to every list request while recording.
    final fake = FakeCameraTransport()..refuseListWhileRecording = true;
    final c = makeContainer(fake);
    await settle(c);
    await c.read(sessionProvider.notifier).connect('NoodleCam', 'secret');
    final s = await settle(c);

    expect(s.filesError, isNull);
    expect(s.files, hasLength(6));
    expect(
      fake.requests.where((u) => u.endsWith('/Novatek/Movie/')),
      isNotEmpty,
    );
    // The clips being recorded are still spotted, though the page rounds sizes.
    expect(s.writing, {
      '/Novatek/Movie/2026_1011_195621_047A.TS',
      '/Novatek/Movie/2026_1011_195621_048B.TS',
    });
    expect(fake.recordingSeconds, greaterThan(0));
  });

  test(
    'with no list and no page, recording can be paused to read it',
    () async {
      final fake = FakeCameraTransport()
        ..refuseListWhileRecording = true
        ..folderPageAvailable = false;
      final c = makeContainer(fake);
      await settle(c);
      await c.read(sessionProvider.notifier).connect('NoodleCam', 'secret');
      var s = await settle(c);
      expect(s.files, isEmpty);
      expect(
        s.filesError!(english),
        contains("won't send its list while recording"),
      );

      fake.requests.clear();
      final problem = await c
          .read(sessionProvider.notifier)
          .refreshPausingRecording();
      s = await settle(c);
      expect(problem, isNull);
      expect(s.files, hasLength(6));
      expect(s.filesError, isNull);
      expect(s.status!.isRecording, isTrue);
      expect(fake.recordingSeconds, greaterThan(0));
      // Stopped, listed, started again, in that order.
      final order = [
        for (final u in fake.requests)
          if (u.contains('cmd=2001') || u.contains('cmd=3015'))
            u.split('cmd=').last,
      ];
      expect(order.first, '2001&par=0');
      expect(order, contains('3015'));
      expect(order.last, '2001&par=1');
    },
  );

  test(
    'pausing to read the list restarts recording even if it fails',
    () async {
      final fake = FakeCameraTransport()
        ..fileListStatus = -3
        ..folderPageAvailable = false;
      final c = makeContainer(fake);
      await settle(c);
      await c.read(sessionProvider.notifier).connect('NoodleCam', 'secret');
      await settle(c);
      final problem = await c
          .read(sessionProvider.notifier)
          .refreshPausingRecording();
      expect(problem!(english), contains('even with recording stopped'));
      expect(fake.recordingSeconds, greaterThan(0));
      expect(c.read(sessionProvider).busy, isFalse);
    },
  );

  test('manual sync sends the time again', () async {
    final fake = FakeCameraTransport();
    final c = makeContainer(fake);
    await settle(c);
    await c.read(sessionProvider.notifier).connect('NoodleCam', 'secret');
    await settle(c);
    await c.read(sessionProvider.notifier).syncTime();
    await settle(c);
    expect(fake.requests.where((u) => u.contains('cmd=3005')), hasLength(2));
  });
}
