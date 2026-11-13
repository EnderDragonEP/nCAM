import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../camera/models.dart';
import '../camera/transport.dart';
import '../downloads/downloader.dart';
import '../state/downloads.dart';
import '../state/session.dart';
import 'diagnostic_screen.dart';
import 'fast_mode.dart';
import 'format.dart';
import 'live_screen.dart';
import 'recordings_screen.dart';
import 'saved_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(recordingGuardProvider);
    final s = ref.watch(sessionProvider);
    final controller = ref.read(sessionProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('nCAM'),
        actions: [
          IconButton(
            tooltip: 'Diagnostic log',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DiagnosticScreen()),
            ),
            icon: const Icon(Icons.receipt_long_outlined),
          ),
          if (s.connected && s.status != null)
            IconButton(
              tooltip: 'Camera settings',
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              ),
              icon: const Icon(Icons.settings_outlined),
            ),
          if (s.connected)
            IconButton(
              tooltip: 'Refresh',
              onPressed: s.busy ? null : controller.refresh,
              icon: const Icon(Icons.refresh),
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: s.busy
              ? const LinearProgressIndicator()
              : const SizedBox(height: 4),
        ),
      ),
      body: !s.loaded
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _LinkCard(state: s),
                const RecordingPausedBanner(margin: EdgeInsets.only(top: 12)),
                if (s.error != null) ...[
                  const SizedBox(height: 12),
                  _ErrorCard(message: s.error!),
                ],
                if (!s.connected && s.link != LinkState.lost) ...[
                  const SizedBox(height: 12),
                  _ConnectCard(state: s),
                ],
                const SizedBox(height: 12),
                const _SavedCard(),
                if (s.connected && s.status != null) ...[
                  const SizedBox(height: 12),
                  _StatusCard(status: s.status!),
                  const SizedBox(height: 12),
                  Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      leading: const Icon(Icons.live_tv_outlined),
                      title: const Text('Live view'),
                      subtitle: const Text(
                        'See what the camera sees right now.',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const LiveScreen(),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _TimeCard(state: s),
                  if (s.filesError != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: const Text('No file list'),
                        subtitle: Text(s.filesError!),
                      ),
                    ),
                  ] else if (s.files != null) ...[
                    const SizedBox(height: 12),
                    _FilesCard(files: s.files!),
                  ],
                ],
              ],
            ),
    );
  }
}

class _SavedCard extends ConsumerWidget {
  const _SavedCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(localFilesProvider).value?.length ?? 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.smartphone),
        title: const Text('Saved on this phone'),
        subtitle: Text(
          count == 0
              ? 'No clips yet'
              : count == 1
              ? '1 clip, playable without the camera'
              : '$count clips, playable without the camera',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const SavedScreen())),
      ),
    );
  }
}

class _LinkCard extends ConsumerWidget {
  const _LinkCard({required this.state});
  final SessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final name = state.saved?.ssid ?? 'camera';
    final (icon, color, title, subtitle) = switch (state.link) {
      LinkState.connected => (
        Icons.wifi,
        scheme.primary,
        'Connected to $name',
        'Only this app uses the camera\'s Wi-Fi. Everything else stays on your '
            'normal internet connection.',
      ),
      LinkState.connecting => (
        Icons.wifi_find,
        scheme.secondary,
        'Joining $name…',
        'Android may ask you to confirm the network.',
      ),
      LinkState.lost => (
        Icons.wifi_off,
        scheme.error,
        'Lost $name',
        'Will rejoin automatically when the camera is back in range.',
      ),
      LinkState.disconnected => (
        Icons.wifi_off,
        scheme.outline,
        'Not connected',
        state.saved == null
            ? 'Enter the camera\'s Wi-Fi name and password once.'
            : 'Saved camera: $name',
      ),
    };
    return Card(
      child: ListTile(
        leading: Icon(icon, color: color, size: 32),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: state.link == LinkState.disconnected
            ? null
            : TextButton(
                onPressed: ref.read(sessionProvider.notifier).disconnect,
                child: const Text('Disconnect'),
              ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
      ),
    );
  }
}

class _ConnectCard extends ConsumerStatefulWidget {
  const _ConnectCard({required this.state});
  final SessionState state;

  @override
  ConsumerState<_ConnectCard> createState() => _ConnectCardState();
}

class _ConnectCardState extends ConsumerState<_ConnectCard> {
  final _ssid = TextEditingController();
  final _password = TextEditingController();
  bool _editing = false;
  bool _showPassword = false;
  bool _scanning = false;

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      final networks = await ref.read(transportProvider).scan();
      if (!mounted) return;
      final picked = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: networks.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No networks found. Make sure Wi-Fi is on, or type the name.',
                  ),
                )
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final n in networks)
                      ListTile(
                        leading: const Icon(Icons.wifi),
                        title: Text(n.ssid),
                        trailing: Text('${n.level} dBm'),
                        onTap: () => Navigator.pop(context, n.ssid),
                      ),
                  ],
                ),
        ),
      );
      if (picked != null) _ssid.text = picked;
    } on TransportException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'permission_denied'
                ? 'Without that permission the app cannot list networks. '
                      'You can still type the name.'
                : 'Scan failed: ${e.message}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final saved = widget.state.saved;
    final busy = widget.state.busy;
    final controller = ref.read(sessionProvider.notifier);

    if (saved != null && !_editing) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton.icon(
                onPressed: busy
                    ? null
                    : () => controller.connect(saved.ssid, saved.password),
                icon: const Icon(Icons.wifi),
                label: Text('Connect to ${saved.ssid}'),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            _ssid.text = saved.ssid;
                            _password.text = saved.password;
                            _editing = true;
                          }),
                    child: const Text('Change name or password'),
                  ),
                  TextButton(
                    onPressed: busy ? null : controller.forget,
                    child: const Text('Forget'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _ssid,
              enabled: !busy,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Camera Wi-Fi name',
                border: const OutlineInputBorder(),
                suffixIcon: _scanning
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        tooltip: 'Find nearby networks',
                        onPressed: busy ? null : _scan,
                        icon: const Icon(Icons.search),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              enabled: !busy,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _showPassword ? 'Hide password' : 'Show password',
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword ? Icons.visibility_off : Icons.visibility,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy
                  ? null
                  : () {
                      final ssid = _ssid.text.trim();
                      if (ssid.isEmpty) return;
                      setState(() => _editing = false);
                      controller.connect(ssid, _password.text);
                    },
              child: const Text('Connect'),
            ),
            if (saved != null)
              TextButton(
                onPressed: busy ? null : () => setState(() => _editing = false),
                child: const Text('Cancel'),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends ConsumerStatefulWidget {
  const _StatusCard({required this.status});
  final CameraStatus status;

  @override
  ConsumerState<_StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends ConsumerState<_StatusCard> {
  bool _starting = false;

  Future<void> _start() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _starting = true);
    final error = await ref.read(sessionProvider.notifier).startRecording();
    if (mounted) setState(() => _starting = false);
    messenger.showSnackBar(
      SnackBar(content: Text(error ?? 'The camera is recording.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final scheme = Theme.of(context).colorScheme;
    // Paused on purpose by fast download: that has its own banner and restart.
    final pausedByApp =
        (ref.watch(fastModeProvider).value?.phase ?? FastPhase.idle) !=
        FastPhase.idle;
    final warn = !status.isRecording && status.hasCard && !pausedByApp;
    return Card(
      child: Column(
        children: [
          if (warn)
            Container(
              color: scheme.errorContainer,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Icon(Icons.warning_amber, color: scheme.onErrorContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'The camera is NOT recording.',
                      style: TextStyle(
                        color: scheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: _starting ? null : _start,
                    child: Text(_starting ? 'Starting…' : 'Start recording'),
                  ),
                ],
              ),
            )
          else
            ListTile(
              leading: Icon(
                status.isRecording
                    ? Icons.fiber_manual_record
                    : Icons.stop_circle_outlined,
                color: status.isRecording ? Colors.red : scheme.outline,
              ),
              title: Text(status.isRecording ? 'Recording' : 'Not recording'),
              subtitle: status.isRecording
                  ? Text(
                      'Current clip: ${formatSpan(Duration(seconds: status.recordingSeconds))}',
                    )
                  : null,
            ),
          ListTile(
            leading: Icon(
              Icons.sd_card_outlined,
              color: status.hasCard ? null : scheme.error,
            ),
            title: Text(status.hasCard ? 'SD card OK' : 'No SD card'),
            subtitle: status.hasCard
                ? Text('${formatBytes(status.freeBytes)} free')
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.memory),
            title: const Text('Firmware'),
            subtitle: Text(status.firmware),
          ),
        ],
      ),
    );
  }
}

class _TimeCard extends ConsumerWidget {
  const _TimeCard({required this.state});
  final SessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final sync = state.timeSync;
    final String title;
    final lines = <String>[];
    if (sync == null) {
      title = 'Camera clock not synced yet';
    } else if (!sync.ok) {
      title = 'Clock sync failed';
      lines.add(sync.error!);
    } else {
      title = 'Clock synced at ${formatClock(sync.at)}';
      final ahead = sync.cameraAheadBy;
      if (ahead == null) {
        lines.add(
          'The camera was not recording, so its previous time could not be checked.',
        );
      } else if (ahead == Duration.zero) {
        lines.add('The camera\'s clock was already right.');
      } else {
        lines.add(
          'Before the sync the camera was ${formatSpan(ahead)} '
          '${ahead.isNegative ? 'behind' : 'ahead'}.',
        );
      }
      lines.add('The new time shows from the next clip on.');
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ListTile(
              leading: Icon(
                sync == null
                    ? Icons.schedule
                    : sync.ok
                    ? Icons.check_circle_outline
                    : Icons.error_outline,
                color: sync != null && !sync.ok ? scheme.error : null,
              ),
              title: Text(title),
              subtitle: lines.isEmpty ? null : Text(lines.join('\n')),
            ),
            OutlinedButton.icon(
              onPressed: state.busy
                  ? null
                  : ref.read(sessionProvider.notifier).syncTime,
              icon: const Icon(Icons.sync),
              label: const Text('Sync time'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilesCard extends ConsumerWidget {
  const _FilesCard({required this.files});
  final List<CameraFile> files;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final total = files.fold<int>(0, (sum, f) => sum + f.size);
    final recordings = ref.watch(recordingsProvider).length;
    final active =
        ref.watch(downloadJobsProvider).value?.where((j) => j.active).length ??
        0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.video_library_outlined),
        title: Text(recordings == 1 ? '1 recording' : '$recordings recordings'),
        subtitle: Text(
          [
            '${files.length} files, ${formatBytes(total)}',
            if (active > 0)
              active == 1 ? '1 download running' : '$active downloads queued',
          ].join(' · '),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const RecordingsScreen()),
        ),
      ),
    );
  }
}
