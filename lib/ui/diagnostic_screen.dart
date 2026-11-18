import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/l10n.dart';
import '../state/session.dart';

/// Shows the app's record of every command it sent the camera and each answer, so a
/// problem can be traced after the fact. "Copy" puts the whole log on the clipboard.
class DiagnosticScreen extends ConsumerStatefulWidget {
  const DiagnosticScreen({super.key});

  @override
  ConsumerState<DiagnosticScreen> createState() => _DiagnosticScreenState();
}

class _DiagnosticScreenState extends ConsumerState<DiagnosticScreen> {
  String? _log;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    String log;
    try {
      log = await ref.read(transportProvider).diagnosticLog();
    } catch (e) {
      if (!mounted) return;
      log = context.l10n.logReadFailed('$e');
    }
    if (mounted) setState(() => _log = log);
  }

  @override
  Widget build(BuildContext context) {
    final log = _log;
    // Newest first: the interesting part is usually the end.
    final lines = (log ?? '').trimRight().split('\n').reversed.toList();
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l.diagnosticLog),
        actions: [
          IconButton(
            tooltip: l.reload,
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            tooltip: l.saveToDownloads,
            onPressed: log == null || log.isEmpty
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    String message;
                    try {
                      final name = await ref
                          .read(transportProvider)
                          .saveDiagnosticLog();
                      message = l.logSaved(name);
                    } catch (e) {
                      message = l.logSaveFailed('$e');
                    }
                    messenger.showSnackBar(SnackBar(content: Text(message)));
                  },
            icon: const Icon(Icons.download),
          ),
          IconButton(
            tooltip: l.copyAll,
            onPressed: log == null || log.isEmpty
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    await Clipboard.setData(ClipboardData(text: log));
                    messenger.showSnackBar(
                      SnackBar(content: Text(l.logCopied)),
                    );
                  },
            icon: const Icon(Icons.copy),
          ),
          IconButton(
            tooltip: l.clear,
            onPressed: () async {
              await ref.read(transportProvider).clearDiagnosticLog();
              await _load();
            },
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: log == null
          ? const Center(child: CircularProgressIndicator())
          : log.trim().isEmpty
          ? Center(child: Text(l.logEmpty))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: lines.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  lines[i],
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ),
    );
  }
}
