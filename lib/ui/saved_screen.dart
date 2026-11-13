import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../camera/models.dart';
import '../camera/recordings.dart';
import '../state/downloads.dart';
import 'clip_thumbnail.dart';
import 'format.dart';
import 'player_screen.dart';

/// Clips already on the phone. Needs no camera connection.
class SavedScreen extends ConsumerWidget {
  const SavedScreen({super.key, this.onBack});

  /// When shown inside the dock, the back arrow returns to the home page.
  final VoidCallback? onBack;

  Future<void> _delete(BuildContext context, WidgetRef ref, Recording r) async {
    final files = r.files;
    final what = files.length == 1 ? '1 file' : '${files.length} files';
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $what from this phone?'),
        content: const Text(
          'Only the copy on the phone is removed. Anything still on the camera stays there.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final downloader = ref.read(downloaderProvider);
    var deleted = 0;
    for (final f in files) {
      try {
        if (await downloader.deleteLocal(f.name)) deleted++;
      } catch (_) {}
    }
    ref.invalidate(localFilesProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          deleted == files.length
              ? 'Deleted from this phone.'
              : 'Deleted $deleted of ${files.length}. The rest could not be removed.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loading = ref.watch(localFilesProvider).isLoading;
    final recordings = ref.watch(savedRecordingsProvider);

    final items = <Widget>[];
    String? lastDay;
    for (final r in recordings) {
      final day = r.time == null ? 'Unknown date' : formatDay(r.time!);
      if (day != lastDay) {
        lastDay = day;
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              day,
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(color: Theme.of(context).colorScheme.primary),
            ),
          ),
        );
      }
      items.add(
        _SavedTile(recording: r, onDelete: () => _delete(context, ref, r)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: onBack == null ? null : BackButton(onPressed: onBack),
        title: const Text('Saved on this phone'),
      ),
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  loading
                      ? 'Looking for saved clips…'
                      : 'Nothing saved yet. Download recordings from the camera and '
                            'they will appear here and in your gallery (Movies/nCAM).',
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : ListView(children: items),
    );
  }
}

class _SavedTile extends StatelessWidget {
  const _SavedTile({required this.recording, required this.onDelete});
  final Recording recording;
  final VoidCallback onDelete;

  void _play(BuildContext context, Lens lens) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(recording: recording, lens: lens),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = recording;
    final first = r.files.first;
    final time = r.time;
    return InkWell(
      onTap: () => _play(context, first.lens),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 12),
              child: ClipThumbnail(key: ValueKey(first.name), file: first),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    time == null ? first.name : formatClock(time),
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final f in r.files)
                        ActionChip(
                          avatar: const Icon(Icons.play_arrow, size: 18),
                          label: Text(
                            '${switch (f.lens) {
                              Lens.front => 'Front',
                              Lens.rear => 'Rear',
                              Lens.unknown => f.name,
                            }} · ${formatBytes(f.size)}',
                          ),
                          onPressed: f.isVideo
                              ? () => _play(context, f.lens)
                              : null,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'More',
              onSelected: (_) => onDelete(),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Delete from this phone'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
