import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../camera/models.dart';
import '../camera/recordings.dart';
import '../l10n/l10n.dart';
import '../state/clip_names.dart';
import '../state/downloads.dart';
import 'clip_thumbnail.dart';
import 'format.dart';
import 'player_screen.dart';
import 'recording_search.dart';

/// Clips already on the phone, with their names, and a search over names and dates.
/// Needs no camera connection.
class SavedScreen extends ConsumerStatefulWidget {
  const SavedScreen({super.key, this.onBack});

  /// When shown inside the dock, the back arrow returns to the home page.
  final VoidCallback? onBack;

  @override
  ConsumerState<SavedScreen> createState() => _SavedScreenState();
}

class _SavedScreenState extends ConsumerState<SavedScreen> {
  final _search = TextEditingController();
  String _query = '';

  /// The search box is open (from the search button, as on Recordings).
  bool _searching = false;

  void _closeSearch() => setState(() {
    _search.clear();
    _query = '';
    _searching = false;
  });

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _delete(Recording r) async {
    final files = r.files;
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l.deleteFromPhoneTitle(files.length)),
        content: Text(l.deleteFromPhoneBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final downloader = ref.read(downloaderProvider);
    final gone = <String>[];
    for (final f in files) {
      try {
        if (await downloader.deleteLocal(f.name)) gone.add(f.name);
      } catch (_) {}
    }
    // A name goes with the last copy of its recording.
    await ref.read(clipNamesProvider.notifier).forget(gone);
    ref.invalidate(localFilesProvider);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          gone.length == files.length
              ? l.deletedFromPhone
              : l.deletedSomeFromPhone(gone.length, files.length),
        ),
      ),
    );
  }

  Future<void> _rename(Recording r, String? current) async {
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _NameDialog(recording: r, current: current),
    );
    if (name == null) return; // cancelled
    await ref.read(clipNamesProvider.notifier).rename(r, name);
  }

  void _setQuery(String text) => setState(() => _query = text.trim());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final loading = ref.watch(localFilesProvider).isLoading;
    final all = ref.watch(savedRecordingsProvider);
    final names = ref.watch(clipNamesProvider);
    final shown = [
      for (final r in all)
        if (recordingMatches(l, r, clipName(names, r), _query)) r,
    ];

    final items = <Widget>[];
    String? lastDay;
    for (final r in shown) {
      final day = r.time == null ? l.unknownDate : formatDay(l, r.time!);
      if (day != lastDay) {
        lastDay = day;
        items.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              day,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
        );
      }
      final name = clipName(names, r);
      items.add(
        _SavedTile(
          recording: r,
          name: name,
          onRename: () => _rename(r, name),
          onDelete: () => _delete(r),
        ),
      );
    }

    final Widget body;
    if (all.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            loading ? l.lookingForSaved : l.nothingSaved,
            textAlign: TextAlign.center,
          ),
        ),
      );
    } else if (shown.isEmpty) {
      body = Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(l.noSavedMatch(_query), textAlign: TextAlign.center),
        ),
      );
    } else {
      body = ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: items,
      );
    }

    return PopScope(
      canPop: !_searching,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeSearch();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: widget.onBack == null
              ? null
              : BackButton(onPressed: widget.onBack),
          title: Text(l.savedTitle),
          actions: [
            IconButton(
              tooltip: l.search,
              onPressed: all.isEmpty || _searching
                  ? null
                  : () => setState(() => _searching = true),
              icon: const Icon(Icons.search),
            ),
          ],
          bottom: !_searching
              ? null
              : PreferredSize(
                  preferredSize: const Size.fromHeight(64),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: SearchBar(
                      controller: _search,
                      autoFocus: true,
                      hintText: l.searchHint,
                      leading: const Icon(Icons.search),
                      elevation: const WidgetStatePropertyAll(0),
                      onChanged: _setQuery,
                      trailing: [
                        IconButton(
                          tooltip: l.closeSearch,
                          icon: const Icon(Icons.close),
                          onPressed: _closeSearch,
                        ),
                      ],
                    ),
                  ),
                ),
        ),
        body: body,
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.recording, required this.current});
  final Recording recording;
  final String? current;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _text = TextEditingController(text: widget.current ?? '');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final time = widget.recording.time;
    final l = context.l10n;
    return AlertDialog(
      title: Text(widget.current == null ? l.nameRecording : l.renameRecording),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (time != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(formatDateTime(time)),
            ),
          TextField(
            controller: _text,
            autofocus: true,
            maxLength: clipNameMaxLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: l.nameLabel,
              hintText: l.nameHint,
            ),
            onSubmitted: (v) => Navigator.pop(context, v),
          ),
        ],
      ),
      actions: [
        if (widget.current != null)
          TextButton(
            onPressed: () => Navigator.pop(context, ''),
            child: Text(l.removeName),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _text.text),
          child: Text(l.save),
        ),
      ],
    );
  }
}

class _SavedTile extends StatelessWidget {
  const _SavedTile({
    required this.recording,
    required this.name,
    required this.onRename,
    required this.onDelete,
  });
  final Recording recording;
  final String? name;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  void _play(BuildContext context, Lens lens) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(recording: recording, lens: lens),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = context.l10n;
    final r = recording;
    final first = r.files.first;
    final time = r.time;
    final clock = time == null ? first.name : formatClock(time);
    return InkWell(
      onTap: () => _play(context, first.lens),
      onLongPress: onRename,
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
                  Text(name ?? clock, style: theme.textTheme.titleMedium),
                  if (name != null)
                    Text(clock, style: theme.textTheme.bodySmall),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final f in r.files)
                        ActionChip(
                          avatar: const Icon(Icons.play_arrow, size: 18),
                          label: Text(
                            l.chipSize(switch (f.lens) {
                              Lens.front => l.front,
                              Lens.rear => l.rear,
                              Lens.unknown => f.name,
                            }, formatBytes(f.size)),
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
              tooltip: l.more,
              onSelected: (action) =>
                  action == 'rename' ? onRename() : onDelete(),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'rename',
                  child: Text(name == null ? l.nameMenu : l.renameMenu),
                ),
                PopupMenuItem(value: 'delete', child: Text(l.deleteFromPhone)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
