import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../camera/models.dart';
import '../camera/transport.dart';
import '../downloads/downloader.dart';
import '../l10n/l10n.dart';
import '../state/downloads.dart';
import '../state/session.dart';
import '../state/sync_on_connect.dart';
import 'diagnostic_screen.dart';
import 'fast_mode.dart';
import 'format.dart';
import 'app_shell.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(recordingGuardProvider);
    final s = ref.watch(sessionProvider);
    final controller = ref.read(sessionProvider.notifier);
    final l = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l.appTitle),
        actions: [
          IconButton(
            tooltip: l.diagnosticLog,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const DiagnosticScreen()),
            ),
            icon: const Icon(Icons.receipt_long_outlined),
          ),
          // Opens inside the app frame, so the dock stays and Back returns here.
          IconButton(
            tooltip: l.settingsTitle,
            onPressed: () =>
                ref.read(shellTabProvider.notifier).show(ShellTab.settings),
            icon: const Icon(Icons.settings_outlined),
          ),
          if (s.connected)
            IconButton(
              tooltip: l.refresh,
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
              // The floating dock sits over the bottom of the page.
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                16 + MediaQuery.paddingOf(context).bottom,
              ),
              children: [
                _LinkCard(state: s),
                const RecordingPausedBanner(margin: EdgeInsets.only(top: 12)),
                if (s.error != null) ...[
                  const SizedBox(height: 12),
                  _ErrorCard(message: s.error!(l)),
                ],
                if (!s.connected && s.link != LinkState.lost) ...[
                  const SizedBox(height: 12),
                  _ConnectCard(state: s),
                ],
                if (s.connected && s.status != null) ...[
                  const SizedBox(height: 12),
                  _StatusCard(status: s.status!, statusAt: s.statusAt),
                  const SizedBox(height: 12),
                  _TimeCard(state: s),
                  if (s.filesError != null) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: Text(l.noFileList),
                        subtitle: Text(s.filesError!(l)),
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

class _LinkCard extends ConsumerWidget {
  const _LinkCard({required this.state});
  final SessionState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final l = context.l10n;
    final name = state.saved?.ssid ?? l.defaultCameraName;
    final (icon, color, title, subtitle) = switch (state.link) {
      LinkState.connected => (
        Icons.wifi,
        scheme.primary,
        l.linkConnected(name),
        l.linkConnectedHint,
      ),
      LinkState.connecting => (
        Icons.wifi_find,
        scheme.secondary,
        l.linkJoining(name),
        l.linkJoiningHint,
      ),
      LinkState.lost => (
        Icons.wifi_off,
        scheme.error,
        l.linkLost(name),
        l.linkLostHint,
      ),
      LinkState.disconnected => (
        Icons.wifi_off,
        scheme.outline,
        l.notConnected,
        state.saved == null ? l.linkFirstTime : l.linkSaved(name),
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
                // The same action, named for what it does at the time: stop
                // trying while joining or rejoining, leave once connected.
                onPressed: ref.read(sessionProvider.notifier).disconnect,
                child: Text(
                  state.link == LinkState.connected ? l.disconnect : l.cancel,
                ),
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
    final l = context.l10n;
    setState(() => _scanning = true);
    try {
      final networks = await ref.read(transportProvider).scan();
      if (!mounted) return;
      final picked = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: networks.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(l.scanNone),
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
                ? l.scanNoPermission
                : l.scanFailed(e.message),
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
    final l = context.l10n;

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
                label: Text(l.connectTo(saved.ssid)),
              ),
              const SizedBox(height: 8),
              // Wraps instead of overflowing with large system text.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            _ssid.text = saved.ssid;
                            _password.text = saved.password;
                            _editing = true;
                          }),
                    child: Text(l.changeNameOrPassword),
                  ),
                  TextButton(
                    onPressed: busy ? null : controller.forget,
                    child: Text(l.forget),
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
                labelText: l.cameraWifiName,
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
                        tooltip: l.findNetworks,
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
                labelText: l.password,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _showPassword ? l.hidePassword : l.showPassword,
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
              child: Text(l.connect),
            ),
            if (saved != null)
              TextButton(
                onPressed: busy ? null : () => setState(() => _editing = false),
                child: Text(l.cancel),
              ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends ConsumerStatefulWidget {
  const _StatusCard({required this.status, required this.statusAt});
  final CameraStatus status;
  final DateTime? statusAt;

  @override
  ConsumerState<_StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends ConsumerState<_StatusCard> {
  bool _starting = false;

  Future<void> _start() async {
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    setState(() => _starting = true);
    final error = await ref.read(sessionProvider.notifier).startRecording();
    if (mounted) setState(() => _starting = false);
    messenger.showSnackBar(
      SnackBar(content: Text(error?.call(l) ?? l.nowRecording)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final scheme = Theme.of(context).colorScheme;
    final l = context.l10n;
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
                      l.notRecordingWarning,
                      style: TextStyle(
                        color: scheme.onErrorContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: _starting ? null : _start,
                    child: Text(_starting ? l.starting : l.startRecording),
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
              title: Text(status.isRecording ? l.recording : l.notRecording),
              subtitle: status.isRecording
                  ? ClipTimer(
                      seconds: status.recordingSeconds,
                      readAt: widget.statusAt,
                    )
                  : null,
            ),
          ListTile(
            leading: Icon(
              Icons.sd_card_outlined,
              color: status.hasCard ? null : scheme.error,
            ),
            title: Text(status.hasCard ? l.sdCardOk : l.noSdCard),
            subtitle: status.hasCard
                ? Text(l.freeSpace(formatBytes(status.freeBytes)))
                : null,
          ),
          ListTile(
            leading: const Icon(Icons.memory),
            title: Text(l.firmware),
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
    final l = context.l10n;
    final sync = state.timeSync;
    final String title;
    final lines = <String>[];
    if (sync == null) {
      title = l.clockNotSynced;
      if (!ref.watch(syncOnConnectProvider)) lines.add(l.syncOnConnectIsOff);
    } else if (!sync.ok) {
      title = l.clockSyncFailed;
      lines.add(sync.error!);
    } else {
      title = l.clockSyncedAt(formatClock(sync.at));
      final ahead = sync.cameraAheadBy;
      if (ahead == null) {
        lines.add(l.clockNotChecked);
      } else if (ahead == Duration.zero) {
        lines.add(l.clockWasRight);
      } else {
        final span = formatSpan(l, ahead);
        lines.add(
          ahead.isNegative ? l.clockWasBehind(span) : l.clockWasAhead(span),
        );
      }
      lines.add(l.clockNextClip);
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
              label: Text(l.syncTime),
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
    final l = context.l10n;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: const Icon(Icons.video_library_outlined),
        title: Text(l.recordingCount(recordings)),
        subtitle: Text(
          [
            l.filesAndSize(files.length, formatBytes(total)),
            if (active > 0) l.downloadsActive(active),
          ].join(' · '),
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: () =>
            ref.read(shellTabProvider.notifier).show(ShellTab.recordings),
      ),
    );
  }
}

/// "Current clip: 4 min 10 s", counting up every second between readings from the
/// camera. The camera is asked again every few seconds, which corrects the count when a
/// new clip starts.
class ClipTimer extends StatefulWidget {
  const ClipTimer({super.key, required this.seconds, required this.readAt});

  /// The camera's count when it was read.
  final int seconds;
  final DateTime? readAt;

  @override
  State<ClipTimer> createState() => _ClipTimerState();
}

class _ClipTimerState extends State<ClipTimer> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final readAt = widget.readAt;
    final since = readAt == null
        ? 0
        : DateTime.now().difference(readAt).inSeconds;
    final seconds = widget.seconds + (since < 0 ? 0 : since);
    final l = context.l10n;
    return Text(l.currentClip(formatSpan(l, Duration(seconds: seconds))));
  }
}
