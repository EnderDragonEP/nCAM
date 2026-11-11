import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../camera/models.dart';
import '../state/thumbnails.dart';

/// Preview picture for a clip on the camera, loaded when the row first appears.
class ClipThumbnail extends ConsumerStatefulWidget {
  const ClipThumbnail({super.key, required this.file, this.width = 96});
  final CameraFile file;
  final double width;

  @override
  ConsumerState<ClipThumbnail> createState() => _ClipThumbnailState();
}

class _ClipThumbnailState extends ConsumerState<ClipThumbnail> {
  late ThumbnailLoader _loader;
  String? _path;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _loader = ref.read(thumbnailLoaderProvider);
    _load();
  }

  @override
  void didUpdateWidget(ClipThumbnail old) {
    super.didUpdateWidget(old);
    if (old.file.name != widget.file.name) {
      _loader.cancel(old.file);
      _path = null;
      _load();
    }
  }

  void _load() {
    final file = widget.file;
    _path = _loader.cached(file);
    if (_path != null) return;
    _loading = true;
    _loader.load(file).then((path) {
      if (!mounted || widget.file.name != file.name) return;
      setState(() {
        _path = path;
        _loading = false;
      });
    });
  }

  @override
  void dispose() {
    _loader.cancel(widget.file);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final path = _path;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: widget.width,
        height: widget.width * 9 / 16,
        color: scheme.surfaceContainerHighest,
        child: path != null
            ? Image.file(
                File(path),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _placeholder(scheme),
              )
            : _loading
            ? const Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : _placeholder(scheme),
      ),
    );
  }

  Widget _placeholder(ColorScheme scheme) =>
      Icon(Icons.movie_outlined, color: scheme.outline);
}
