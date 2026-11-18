import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ncam/l10n/l10n.dart';
import 'package:ncam/camera/camera_api.dart';
import 'package:ncam/camera/fake_transport.dart';
import 'package:ncam/camera/novatek_parsers.dart';
import 'package:ncam/state/credentials.dart';
import 'package:ncam/state/live.dart';
import 'package:ncam/state/session.dart';

Future<void> tick([int times = 20]) async {
  for (var i = 0; i < times; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('parses the live view link and current values from real replies', () {
    expect(
      parseLiveViewLink(
        '<?xml version="1.0" encoding="UTF-8" ?>\n<LIST>\n'
        '<MovieLiveViewLink>http://192.168.1.254:8192</MovieLiveViewLink>\n'
        '<PhotoLiveViewLink>http://192.168.1.254:8192</PhotoLiveViewLink>\n</LIST>\n',
      ),
      'http://192.168.1.254:8192',
    );
    final values = parseCurrentValues(
      '<?xml version="1.0" encoding="UTF-8" ?>\n<Function>\n<Cmd>2003</Cmd>\n'
      '<Status>3</Status>\n<Cmd>2022</Cmd>\n<Status>8000</Status>\n'
      '<Cmd>3028</Cmd>\n<Status>2</Status>\n</Function>',
    );
    expect(values, {2003: '3', 2022: '8000', 3028: '2'});
  });

  group('LiveController', () {
    late FakeCameraTransport camera;
    late ProviderContainer c;

    Future<void> open({
      Duration startTimeout = const Duration(hours: 1),
    }) async {
      await camera.connect(ssid: 'NoodleCam', password: 'x');
      c = ProviderContainer(
        overrides: [
          transportProvider.overrideWithValue(camera),
          credentialStoreProvider.overrideWithValue(MemoryCredentialStore()),
          liveStartTimeoutProvider.overrideWithValue(startTimeout),
          liveRetryDelayProvider.overrideWithValue(Duration.zero),
        ],
      );
      addTearDown(c.dispose);
      c.listen(liveProvider, (_, _) {});
      await tick();
    }

    setUp(() => camera = FakeCameraTransport());

    test('opens the stream the camera advertises and shows frames', () async {
      await open();
      expect(camera.liveOpened, ['http://192.168.1.254:8192']);
      expect(camera.screenKeptOn, isTrue);
      expect(c.read(liveProvider).status, LiveStatus.connecting);
      expect(c.read(liveProvider).viewIndex, 2);

      expect(camera.emitFrame([0xFF, 0xD8, 1, 0xFF, 0xD9]), isTrue);
      await tick();
      final s = c.read(liveProvider);
      expect(s.status, LiveStatus.playing);
      expect(s.frame, [0xFF, 0xD8, 1, 0xFF, 0xD9]);
      // A camera that streams by itself is never sent the start command.
      expect(camera.requests.where((u) => u.contains('cmd=2015')), isEmpty);
    });

    test('asks the camera to start once when no picture arrives', () async {
      camera.liveNeedsStart = true;
      await open(startTimeout: Duration.zero);
      await tick();
      expect(camera.requests.where((u) => u.contains('cmd=2015&par=1')), [
        isNotNull,
      ]);
      expect(camera.liveOpened, hasLength(2));
    });

    test('gives up with a message if the camera stays silent', () async {
      await open(startTimeout: Duration.zero);
      await tick(60);
      final s = c.read(liveProvider);
      expect(s.status, LiveStatus.failed);
      expect(s.message!(english), contains("isn't sending a picture"));
      expect(
        camera.requests.where((u) => u.contains('cmd=2015')),
        hasLength(1),
      );
    });

    test('reopens a stream that breaks and keeps the last picture', () async {
      await open();
      camera.emitFrame();
      await tick();
      camera.breakLive('SocketTimeoutException');
      await tick();
      expect(camera.liveOpened, hasLength(2));
      expect(c.read(liveProvider).frame, isNotNull);
      camera.emitFrame();
      await tick();
      expect(c.read(liveProvider).status, LiveStatus.playing);
    });

    test('stops after repeated failures and can be retried', () async {
      await open();
      for (var i = 0; i < 4; i++) {
        camera.breakLive('down');
        await tick();
      }
      expect(c.read(liveProvider).status, LiveStatus.failed);
      final opened = camera.liveOpened.length;
      c.read(liveProvider.notifier).retry();
      await tick();
      expect(camera.liveOpened.length, opened + 1);
      expect(c.read(liveProvider).status, LiveStatus.connecting);
    });

    test('waits out a lost camera link and reopens when it is back', () async {
      await open();
      camera.emitFrame();
      await tick();
      expect(c.read(liveProvider).status, LiveStatus.playing);

      // Seen on the real phone: Android reports the link lost mid-stream.
      camera.dropLink();
      await tick();
      final waiting = c.read(liveProvider);
      expect(waiting.status, LiveStatus.connecting);
      expect(waiting.message!(english), contains('Connection lost'));
      expect(waiting.frame, isNotNull);
      // Losing the link is not counted as a stream failure, however long it lasts.
      camera.breakLive('not connected');
      await tick();
      expect(c.read(liveProvider).status, LiveStatus.connecting);
      expect(camera.liveOpened, hasLength(1));

      camera.restoreLink();
      await tick();
      expect(camera.liveOpened, hasLength(2));
      camera.emitFrame();
      await tick();
      expect(c.read(liveProvider).status, LiveStatus.playing);
    });

    test('switches the camera view', () async {
      await open();
      expect(await c.read(liveProvider.notifier).setView(0), isNull);
      expect(camera.viewIndex, 0);
      expect(c.read(liveProvider).viewIndex, 0);
      expect(
        camera.requests.last,
        NovatekCameraApi(camera).commandUrl(3028, par: 0),
      );
    });

    test(
      'closing the screen stops the stream and releases the screen',
      () async {
        await open();
        c.dispose();
        await tick();
        expect(camera.emitFrame(), isFalse);
        expect(camera.screenKeptOn, isFalse);
      },
    );
  });
}
