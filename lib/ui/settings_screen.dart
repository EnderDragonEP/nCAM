import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../camera/models.dart';
import '../state/session.dart';
import '../state/settings.dart';
import 'format.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// What is in progress, shown in place of the list's progress bar. Null when idle.
  String? _working;

  Future<void> _run(String label, Future<String?> Function() action) async {
    if (_working != null) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _working = label);
    String? message;
    try {
      message = await action();
    } finally {
      if (mounted) setState(() => _working = null);
    }
    if (message != null) {
      messenger.showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 6)),
      );
    }
  }

  SettingsController get _controller => ref.read(settingsProvider.notifier);

  Future<void> _choose(CameraSetting setting) async {
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(settingTitles[setting.name] ?? setting.name),
        children: [
          for (final o in setting.options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, o.index),
              child: Row(
                children: [
                  Icon(
                    o.index == setting.value
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Text(prettyOption(o.label)),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null || picked == setting.value) return;
    await _run('Changing setting…', () => _controller.change(setting, picked));
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok == true;
  }

  Future<void> _format() async {
    final ok = await _confirm(
      title: 'Format the SD card?',
      body:
          'Every recording on the camera is erased. This cannot be undone.\n\n'
          'Clips already saved on this phone are kept. Recording is paused during '
          'the format and restarted afterwards.',
      action: 'Erase everything',
    );
    if (ok) await _run('Formatting the card…', _controller.formatCard);
  }

  Future<void> _reset() async {
    final ok = await _confirm(
      title: 'Restore factory settings?',
      body:
          'All camera settings go back to their defaults. That can include the '
          'Wi-Fi name and password, in which case this app will lose the '
          'connection until you enter the default ones.',
      action: 'Reset camera',
    );
    if (ok) await _run('Resetting the camera…', _controller.factoryReset);
  }

  Future<void> _wifi() async {
    final current = ref.read(sessionProvider).saved;
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => _WifiDialog(ssid: current?.ssid ?? ''),
    );
    if (result == null) return;
    await _run(
      'Changing the camera\'s Wi-Fi…',
      () async =>
          await ref
              .read(sessionProvider.notifier)
              .changeWifi(result.$1, result.$2) ??
          'Connected to "${result.$1}" with the new password.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final status = ref.watch(sessionProvider.select((s) => s.status));
    final theme = Theme.of(context);
    final busy = _working != null;

    Widget header(String text) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Camera settings'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: busy || settings.isLoading
              ? const LinearProgressIndicator()
              : const SizedBox(height: 4),
        ),
      ),
      body: ListView(
        children: [
          if (busy)
            ListTile(
              leading: const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              title: Text(_working!),
            ),
          if (status?.isRecording ?? false)
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('The camera is recording'),
              subtitle: Text(
                'If a change makes it stop, the app starts recording again.',
              ),
            ),
          header('Camera'),
          ...settings.when(
            loading: () => const [ListTile(title: Text('Reading settings…'))],
            error: (e, _) => [
              ListTile(
                leading: Icon(
                  Icons.error_outline,
                  color: theme.colorScheme.error,
                ),
                title: const Text('Could not read the settings'),
                subtitle: Text('$e'),
                trailing: TextButton(
                  onPressed: () => ref.invalidate(settingsProvider),
                  child: const Text('Retry'),
                ),
              ),
            ],
            data: (data) => [
              for (final s in data.listed) _settingTile(s, busy),
              if (data.other.isNotEmpty)
                ExpansionTile(
                  leading: const Icon(Icons.list_alt),
                  title: const Text('Other values (read-only)'),
                  subtitle: const Text(
                    'Reported by the camera without any choices to pick from.',
                  ),
                  children: [
                    for (final e
                        in data.other.entries.toList()
                          ..sort((a, b) => a.key.compareTo(b.key)))
                      ListTile(
                        dense: true,
                        title: Text(
                          otherValueTitles[e.key] ?? 'Setting ${e.key}',
                        ),
                        trailing: Text(e.value),
                      ),
                  ],
                ),
            ],
          ),
          header('Wi-Fi'),
          ListTile(
            leading: const Icon(Icons.wifi_password),
            title: const Text('Change Wi-Fi name and password'),
            subtitle: const Text(
              'The camera restarts its Wi-Fi and the app reconnects.',
            ),
            enabled: !busy,
            onTap: _wifi,
          ),
          header('Storage'),
          if (status != null)
            ListTile(
              leading: const Icon(Icons.sd_card_outlined),
              title: Text(status.hasCard ? 'SD card' : 'No SD card'),
              subtitle: status.hasCard
                  ? Text('${formatBytes(status.freeBytes)} free')
                  : null,
            ),
          ListTile(
            leading: Icon(Icons.delete_forever, color: theme.colorScheme.error),
            title: const Text('Format SD card'),
            subtitle: const Text('Erases every recording on the camera.'),
            enabled: !busy && (status?.hasCard ?? true),
            onTap: _format,
          ),
          header('Device'),
          if (status != null)
            ListTile(
              leading: const Icon(Icons.memory),
              title: const Text('Firmware'),
              subtitle: Text(status.firmware),
            ),
          ListTile(
            leading: Icon(Icons.restart_alt, color: theme.colorScheme.error),
            title: const Text('Restore factory settings'),
            enabled: !busy,
            onTap: _reset,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _settingTile(CameraSetting s, bool busy) {
    final title = settingTitles[s.name] ?? s.name;
    final current = s.current;
    final labels = {for (final o in s.options) o.label};

    if (!s.changeable) {
      return ListTile(
        title: Text(title),
        subtitle: const Text('Fixed on this camera'),
        trailing: Text(current == null ? '—' : prettyOption(current.label)),
      );
    }
    // Exactly OFF and ON: a switch.
    if (labels.length == 2 && labels.containsAll(const ['ON', 'OFF'])) {
      final on = s.options.firstWhere((o) => o.label == 'ON');
      final off = s.options.firstWhere((o) => o.label == 'OFF');
      return SwitchListTile(
        title: Text(title),
        value: s.value == on.index,
        onChanged: busy
            ? null
            : (v) => _run(
                'Changing setting…',
                () => _controller.change(s, v ? on.index : off.index),
              ),
      );
    }
    return ListTile(
      title: Text(title),
      trailing: Text(current == null ? '—' : prettyOption(current.label)),
      enabled: !busy,
      onTap: () => _choose(s),
    );
  }
}

class _WifiDialog extends StatefulWidget {
  const _WifiDialog({required this.ssid});
  final String ssid;

  @override
  State<_WifiDialog> createState() => _WifiDialogState();
}

class _WifiDialogState extends State<_WifiDialog> {
  late final _ssid = TextEditingController(text: widget.ssid);
  final _password = TextEditingController();
  bool _show = true;
  String? _error;

  @override
  void dispose() {
    _ssid.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Plain ASCII only: the camera's handling of anything else is unknown.
  static bool _plain(String s) => RegExp(r'^[\x21-\x7E]+$').hasMatch(s);

  void _submit() {
    final ssid = _ssid.text.trim();
    final password = _password.text;
    String? error;
    if (ssid.isEmpty || ssid.length > 32 || !_plain(ssid)) {
      error = 'Name: 1 to 32 letters, digits or symbols, no spaces.';
    } else if (password.length < 8 ||
        password.length > 63 ||
        !_plain(password)) {
      error = 'Password: 8 to 63 letters, digits or symbols, no spaces.';
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, (ssid, password));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Camera Wi-Fi'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ssid,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(labelText: 'Wi-Fi name'),
          ),
          TextField(
            controller: _password,
            obscureText: !_show,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'New password',
              suffixIcon: IconButton(
                tooltip: _show ? 'Hide password' : 'Show password',
                onPressed: () => setState(() => _show = !_show),
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _error ??
                'Write the new password down. If it is lost, the only way back in '
                    'is the reset button on the camera.',
            style: TextStyle(
              color: _error == null
                  ? null
                  : Theme.of(context).colorScheme.error,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Change')),
      ],
    );
  }
}
