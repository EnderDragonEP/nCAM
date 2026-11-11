import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../camera/models.dart';
import '../camera/recordings.dart';
import '../downloads/downloader.dart';
import '../state/downloads.dart';
import '../state/session.dart';
import 'fast_mode.dart';
import 'format.dart';

enum LensFilter { both, front, rear }

class RecordingsScreen extends ConsumerStatefulWidget {
  const RecordingsScreen({super.key});

  @override
  ConsumerState<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends ConsumerState<RecordingsScreen> {
  LensFilter _filter = LensFilter.both;
  bool _selecting = false;
  final Set<String> _selected = {};

  /// The files of [r] that the current filter shows.
  List<CameraFile> _visibleFiles(Recording r) => [
    if (_filter != LensFilter.rear) ?r.front,
    if (_filter != LensFilter.front) ?r.rear,
    ?r.other,
  ];

  void _toggle(Recording r) => setState(() {
    if (!_selected.remove(r.id)) _selected.add(r.id);
    if (_selected.isEmpty) _selecting = false;
  });

  void _stopSelecting() => setState(() {
    _selecting = false;
    _selected.clear();
  });

  Future<void> _download(List<CameraFile> files) async {
    final resolver = ref.read(fileStatusProvider);
    final requests = [
      for (final f in files)
        if (resolver.view(f).downloadable) downloadRequestFor(f),
    ];
    final messenger = ScaffoldMessenger.of(context);
    if (requests.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Nothing to download: already saved or in the queue.'),
        ),
      );
      return;
    }
    try {
      await ref.read(downloaderProvider).enqueue(requests);
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not start the download: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(recordingGuardProvider);
    final session = ref.watch(sessionProvider);
    final recordings = ref
        .watch(recordingsProvider)
        .where((r) => _visibleFiles(r).isNotEmpty)
        .toList();
    final resolver = ref.watch(fileStatusProvider);
    final jobs = ref.watch(downloadJobsProvider).value ?? const [];

    final items = <Widget>[];
    String? lastDay;
    for (final r in recordings) {
      final day = r.time == null ? 'Unknown date' : formatDay(r.time!);
      if (day != lastDay) {
        lastDay = day;
        items.add(_DayHeader(day));
      }
      items.add(
        _RecordingTile(
          recording: r,
          views: [for (final f in _visibleFiles(r)) resolver.view(f)],
          selecting: _selecting,
          selected: _selected.contains(r.id),
          onTap: _selecting && !r.beingWritten ? () => _toggle(r) : null,
          onLongPress: r.beingWritten
              ? null
              : () => setState(() {
                  _selecting = true;
                  _selected.add(r.id);
                }),
          onFile: _onFile,
        ),
      );
    }

    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stopSelecting();
      },
      child: Scaffold(
        appBar: _selecting
            ? AppBar(
                leading: IconButton(
                  tooltip: 'Cancel selection',
                  onPressed: _stopSelecting,
                  icon: const Icon(Icons.close),
                ),
                title: Text('${_selected.length} selected'),
                actions: [
                  IconButton(
                    tooltip: 'Select all',
                    onPressed: () => setState(() {
                      _selected.addAll([
                        for (final r in recordings)
                          if (!r.beingWritten) r.id,
                      ]);
                    }),
                    icon: const Icon(Icons.select_all),
                  ),
                  IconButton(
                    tooltip: 'Download selected',
                    onPressed: () {
                      final files = [
                        for (final r in recordings)
                          if (_selected.contains(r.id)) ..._visibleFiles(r),
                      ];
                      _stopSelecting();
                      _download(files);
                    },
                    icon: const Icon(Icons.download),
                  ),
                ],
              )
            : AppBar(
                title: const Text('Recordings'),
                actions: [
                  IconButton(
                    tooltip: 'Select several',
                    onPressed: recordings.isEmpty
                        ? null
                        : () => setState(() => _selecting = true),
                    icon: const Icon(Icons.checklist),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    onPressed: session.busy || !session.connected
                        ? null
                        : ref.read(sessionProvider.notifier).refresh,
                    icon: const Icon(Icons.refresh),
                  ),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(4),
                  child: session.busy
                      ? const LinearProgressIndicator()
                      : const SizedBox(height: 4),
                ),
              ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: SegmentedButton<LensFilter>(
                segments: const [
                  ButtonSegment(
                    value: LensFilter.both,
                    label: Text('Front + rear'),
                  ),
                  ButtonSegment(value: LensFilter.front, label: Text('Front')),
                  ButtonSegment(value: LensFilter.rear, label: Text('Rear')),
                ],
                selected: {_filter},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _filter = s.first),
              ),
            ),
            const FastModeSwitch(),
            const RecordingPausedBanner(
              margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          session.connected
                              ? (session.busy
                                    ? 'Reading the card…'
                                    : 'No recordings on the card.')
                              : 'Connect to the camera to see its recordings.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: ref.read(sessionProvider.notifier).refresh,
                      child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: items,
                      ),
                    ),
            ),
            _QueueBar(jobs: jobs),
          ],
        ),
      ),
    );
  }

  void _onFile(FileView v) {
    final downloader = ref.read(downloaderProvider);
    switch (v.status) {
      case FileStatus.onCamera:
        _download([v.file]);
      case FileStatus.failed:
        final job = v.job;
        if (job != null) {
          downloader.retry(job.id);
        } else {
          _download([v.file]);
        }
      case FileStatus.queued || FileStatus.running || FileStatus.waiting:
        final job = v.job;
        if (job != null) downloader.cancel(job.id);
      case FileStatus.saved:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${v.file.name} is in your gallery (Movies/nCAM).'),
          ),
        );
      case FileStatus.writing:
        break;
    }
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _RecordingTile extends StatelessWidget {
  const _RecordingTile({
    required this.recording,
    required this.views,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onFile,
  });

  final Recording recording;
  final List<FileView> views;
  final bool selecting;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final void Function(FileView) onFile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = recording;
    final time = r.time;
    final length = r.length;
    final title = [
      time == null ? r.files.first.name : formatClock(time),
      if (length != null) formatSpan(length),
    ].join(' · ');

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        color: selected ? theme.colorScheme.secondaryContainer : null,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 16),
              child: selecting
                  ? Icon(
                      r.beingWritten
                          ? Icons.block
                          : selected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: r.beingWritten
                          ? theme.colorScheme.outline
                          : theme.colorScheme.primary,
                    )
                  : Icon(
                      r.beingWritten
                          ? Icons.fiber_manual_record
                          : Icons.movie_outlined,
                      color: r.beingWritten ? Colors.red : null,
                    ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  if (r.beingWritten)
                    Text(
                      'Recording now. Available when this clip is finished.',
                      style: theme.textTheme.bodySmall,
                    ),
                  if (r.nameDateSuspect && r.start != null)
                    Text(
                      'The camera\'s clock was wrong when this clip started: its '
                      'file name says ${formatDateTime(r.start!)}.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final v in views)
                        _FileChip(
                          view: v,
                          onPressed: selecting ? null : () => onFile(v),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileChip extends StatelessWidget {
  const _FileChip({required this.view, required this.onPressed});
  final FileView view;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lens = switch (view.file.lens) {
      Lens.front => 'Front',
      Lens.rear => 'Rear',
      Lens.unknown => view.file.name,
    };
    final size = formatBytes(view.file.size);
    final job = view.job;
    final percent = job?.fraction == null
        ? ''
        : ' ${(job!.fraction! * 100).floor()}%';

    final (Widget avatar, String label, String tooltip) = switch (view.status) {
      FileStatus.onCamera => (
        const Icon(Icons.download, size: 18),
        '$lens · $size',
        'Download',
      ),
      FileStatus.writing => (
        const Icon(Icons.fiber_manual_record, size: 18, color: Colors.red),
        '$lens · $size',
        'Still recording',
      ),
      FileStatus.queued => (
        const Icon(Icons.schedule, size: 18),
        '$lens · queued',
        'Tap to cancel',
      ),
      FileStatus.running => (
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            value: job?.fraction,
          ),
        ),
        '$lens ·$percent',
        'Tap to cancel',
      ),
      FileStatus.waiting => (
        const Icon(Icons.wifi_off, size: 18),
        '$lens · retrying$percent',
        'Tap to cancel',
      ),
      FileStatus.failed => (
        Icon(Icons.error_outline, size: 18, color: scheme.error),
        '$lens · failed, tap to resume',
        job?.error ?? 'Download failed',
      ),
      FileStatus.saved => (
        Icon(Icons.check_circle, size: 18, color: scheme.primary),
        '$lens · saved',
        'In your gallery',
      ),
    };
    return Tooltip(
      message: tooltip,
      child: ActionChip(
        avatar: avatar,
        label: Text(label),
        onPressed: view.status == FileStatus.writing ? null : onPressed,
      ),
    );
  }
}

/// Summary of the queue, shown while there is something to report.
class _QueueBar extends ConsumerWidget {
  const _QueueBar({required this.jobs});
  final List<DownloadJob> jobs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = jobs.where((j) => j.active).toList();
    final failed = jobs.where((j) => j.state == DownloadState.failed).toList();
    if (active.isEmpty && failed.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final downloader = ref.read(downloaderProvider);
    final List<Widget> children;

    if (active.isNotEmpty) {
      final current = active.firstWhere(
        (j) => j.state != DownloadState.queued,
        orElse: () => active.first,
      );
      final done = jobs.where((j) => j.state == DownloadState.done).length;
      final remaining = active.fold<int>(
        0,
        (sum, j) => sum + (j.total - j.received).clamp(0, j.total),
      );
      final speed = current.bytesPerSecond;
      final detail = current.state == DownloadState.waiting
          ? 'Connection problem, retrying: ${current.error ?? ''}'
          : [
              if (speed > 0) '${formatBytes(speed)}/s',
              if (speed > 0)
                '${formatSpan(Duration(seconds: remaining ~/ speed))} left',
              if (speed <= 0) 'Starting…',
            ].join(' · ');
      children = [
        Row(
          children: [
            Expanded(
              child: Text(
                'Downloading ${done + 1} of ${done + active.length} · ${current.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            TextButton(
              onPressed: () => downloader.cancel(),
              child: const Text('Cancel all'),
            ),
          ],
        ),
        LinearProgressIndicator(value: current.fraction),
        const SizedBox(height: 6),
        Text(detail, style: theme.textTheme.bodySmall),
      ];
    } else {
      children = [
        Row(
          children: [
            Expanded(
              child: Text(
                failed.length == 1
                    ? '1 download failed: ${failed.first.error ?? ''}'
                    : '${failed.length} downloads failed',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(
              onPressed: () {
                for (final j in failed) {
                  downloader.retry(j.id);
                }
              },
              child: const Text('Resume'),
            ),
            TextButton(
              onPressed: downloader.clearFinished,
              child: const Text('Dismiss'),
            ),
          ],
        ),
      ];
    }

    return Material(
      elevation: 8,
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: children,
          ),
        ),
      ),
    );
  }
}
