import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../camera/models.dart';
import '../l10n/l10n.dart';
import '../state/auto_connect.dart';
import '../state/camera_watch.dart';
import '../state/dock_side.dart';
import '../state/pip.dart';
import '../state/session.dart';
import '../state/settings.dart';
import '../state/sync_on_connect.dart';
import 'appearance_tiles.dart';
import 'format.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key, this.onBack});

  /// When shown inside the dock, the back arrow returns to the home page.
  final VoidCallback? onBack;

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  /// What is in progress, shown in place of the list's progress bar. Null when idle.
  String? _working;

  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Back from Android's settings: the battery choice may have changed.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(batteryUnrestrictedProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _run(String label, Future<Msg?> Function() action) async {
    if (_working != null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l = context.l10n;
    setState(() => _working = label);
    Msg? message;
    try {
      message = await action();
    } finally {
      if (mounted) setState(() => _working = null);
    }
    if (message != null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(message(l)),
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  SettingsController get _controller => ref.read(settingsProvider.notifier);

  Future<void> _choose(CameraSetting setting) async {
    final l = context.l10n;
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(settingTitle(l, setting.name)),
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
                  Text(prettyOption(l, o.label)),
                ],
              ),
            ),
        ],
      ),
    );
    if (picked == null || picked == setting.value) return;
    await _run(l.changingSetting, () => _controller.change(setting, picked));
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
            child: Text(context.l10n.cancel),
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
    final l = context.l10n;
    final ok = await _confirm(
      title: l.formatTitle,
      body: l.formatBody,
      action: l.formatAction,
    );
    if (ok) await _run(l.formatting, _controller.formatCard);
  }

  Future<void> _reset() async {
    final l = context.l10n;
    final ok = await _confirm(
      title: l.resetTitle,
      body: l.resetBody,
      action: l.resetAction,
    );
    if (ok) await _run(l.resetting, _controller.factoryReset);
  }

  Future<void> _wifi() async {
    final l = context.l10n;
    final current = ref.read(sessionProvider).saved;
    final result = await showDialog<(String, String)>(
      context: context,
      builder: (context) => _WifiDialog(ssid: current?.ssid ?? ''),
    );
    if (result == null) return;
    await _run(
      l.changingWifi,
      () async =>
          await ref
              .read(sessionProvider.notifier)
              .changeWifi(result.$1, result.$2) ??
          (AppLocalizations l) => l.wifiChanged(result.$1),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(sessionProvider.select((s) => s.status));
    final connected = ref.watch(
      sessionProvider.select((s) => s.connected && s.status != null),
    );
    // Only read from the camera while connected.
    final settings = connected ? ref.watch(settingsProvider) : null;
    final theme = Theme.of(context);
    final busy = _working != null;
    final l = context.l10n;

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
        leading: widget.onBack == null
            ? null
            : BackButton(onPressed: widget.onBack),
        title: Text(l.settingsTitle),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: busy || (settings?.isLoading ?? false)
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
            ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(l.cameraIsRecording),
              subtitle: Text(l.cameraIsRecordingHint),
            ),
          header(l.sectionApp),
          const AppearanceTiles(),
          SwitchListTile(
            secondary: const Icon(Icons.wifi_find),
            title: Text(l.autoConnect),
            subtitle: Text(l.autoConnectHint),
            value: ref.watch(autoConnectProvider),
            onChanged: ref.read(autoConnectProvider.notifier).set,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.schedule),
            title: Text(l.syncOnConnect),
            subtitle: Text(l.syncOnConnectHint),
            value: ref.watch(syncOnConnectProvider),
            onChanged: ref.read(syncOnConnectProvider.notifier).set,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.picture_in_picture_alt_outlined),
            title: Text(l.autoPip),
            subtitle: Text(l.autoPipHint),
            value: ref.watch(pipAutoEnterProvider),
            onChanged: ref.read(pipAutoEnterProvider.notifier).set,
          ),
          ListTile(
            leading: const Icon(Icons.fiber_manual_record_outlined),
            title: Text(l.recordButton),
            subtitle: Text(l.recordButtonHint),
            trailing: SegmentedButton<RecordButtonSide>(
              segments: [
                for (final s in RecordButtonSide.values)
                  ButtonSegment(
                    value: s,
                    label: Text(switch (s) {
                      RecordButtonSide.left => l.sideLeft,
                      RecordButtonSide.right => l.sideRight,
                    }),
                  ),
              ],
              selected: {ref.watch(recordButtonSideProvider)},
              showSelectedIcon: false,
              onSelectionChanged: (s) =>
                  ref.read(recordButtonSideProvider.notifier).set(s.first),
            ),
          ),
          ..._watchTiles(header),
          if (!connected) ...[
            header(l.sectionCamera),
            ListTile(
              leading: const Icon(Icons.wifi_off),
              title: Text(l.notConnected),
              subtitle: Text(l.connectToChangeSettings),
            ),
          ] else ...[
            header(l.sectionCamera),
            ...settings!.when(
              loading: () => [ListTile(title: Text(l.readingSettings))],
              error: (e, _) => [
                ListTile(
                  leading: Icon(
                    Icons.error_outline,
                    color: theme.colorScheme.error,
                  ),
                  title: Text(l.settingsReadFailed),
                  subtitle: Text('$e'),
                  trailing: TextButton(
                    onPressed: () => ref.invalidate(settingsProvider),
                    child: Text(l.retry),
                  ),
                ),
              ],
              data: (data) => [
                for (final s in data.listed) _settingTile(s, busy),
                if (data.other.isNotEmpty)
                  ExpansionTile(
                    leading: const Icon(Icons.list_alt),
                    title: Text(l.otherValues),
                    subtitle: Text(l.otherValuesHint),
                    children: [
                      for (final e
                          in data.other.entries.toList()
                            ..sort((a, b) => a.key.compareTo(b.key)))
                        ListTile(
                          dense: true,
                          title: Text(otherValueTitle(l, e.key)),
                          trailing: Text(e.value),
                        ),
                    ],
                  ),
              ],
            ),
            header(l.sectionWifi),
            ListTile(
              leading: const Icon(Icons.wifi_password),
              title: Text(l.changeWifi),
              subtitle: Text(l.changeWifiHint),
              enabled: !busy,
              onTap: _wifi,
            ),
            header(l.sectionStorage),
            if (status != null)
              ListTile(
                leading: const Icon(Icons.sd_card_outlined),
                title: Text(status.hasCard ? l.sdCard : l.noSdCard),
                subtitle: status.hasCard
                    ? Text(l.freeSpace(formatBytes(status.freeBytes)))
                    : null,
              ),
            ListTile(
              leading: Icon(
                Icons.delete_forever,
                color: theme.colorScheme.error,
              ),
              title: Text(l.formatSdCard),
              subtitle: Text(l.formatSdCardHint),
              enabled: !busy && (status?.hasCard ?? true),
              onTap: _format,
            ),
            header(l.sectionDevice),
            if (status != null)
              ListTile(
                leading: const Icon(Icons.memory),
                title: Text(l.firmware),
                subtitle: Text(status.firmware),
              ),
            ListTile(
              leading: Icon(Icons.restart_alt, color: theme.colorScheme.error),
              title: Text(l.restoreFactory),
              enabled: !busy,
              onTap: _reset,
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  /// The background clock sync. Needs a saved camera, not a connection.
  List<Widget> _watchTiles(Widget Function(String) header) {
    final l = context.l10n;
    final watch = ref.watch(cameraWatchProvider);
    final controller = ref.read(cameraWatchProvider.notifier);
    final saved = ref.watch(sessionProvider.select((s) => s.saved));
    final platform = ref.read(watchPlatformProvider);
    final unrestricted = ref.watch(batteryUnrestrictedProvider).value ?? false;
    return [
      header(l.sectionBackground),
      SwitchListTile(
        secondary: const Icon(Icons.more_time),
        title: Text(l.watchTitle),
        subtitle: Text(saved == null ? l.watchNeedsCamera : l.watchHint),
        value: watch.enabled,
        onChanged: saved == null && !watch.enabled
            ? null
            : controller.setEnabled,
      ),
      if (watch.enabled) ...[
        SwitchListTile(
          secondary: const Icon(Icons.content_cut),
          title: Text(l.watchNewClip),
          subtitle: Text(l.watchNewClipHint),
          value: watch.newClip,
          onChanged: controller.setNewClip,
        ),
        ListTile(
          leading: Icon(
            unrestricted ? Icons.battery_full : Icons.battery_alert_outlined,
          ),
          title: Text(l.watchBattery),
          subtitle: Text(unrestricted ? l.watchBatteryOk : l.watchBatteryHint),
          onTap: unrestricted
              ? null
              : () async {
                  await platform.askUnrestricted();
                  ref.invalidate(batteryUnrestrictedProvider);
                },
        ),
        ListTile(
          leading: const Icon(Icons.notifications_off_outlined),
          title: Text(l.watchHideNotification),
          subtitle: Text(l.watchHideNotificationHint),
          onTap: platform.openNotificationSettings,
        ),
      ],
    ];
  }

  Widget _settingTile(CameraSetting s, bool busy) {
    final l = context.l10n;
    final title = settingTitle(l, s.name);
    final current = s.current;
    final labels = {for (final o in s.options) o.label};

    if (!s.changeable) {
      return ListTile(
        title: Text(title),
        subtitle: Text(l.fixedOnCamera),
        trailing: Text(current == null ? '—' : prettyOption(l, current.label)),
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
                l.changingSetting,
                () => _controller.change(s, v ? on.index : off.index),
              ),
      );
    }
    return ListTile(
      title: Text(title),
      trailing: Text(current == null ? '—' : prettyOption(l, current.label)),
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
    final l = context.l10n;
    final ssid = _ssid.text.trim();
    final password = _password.text;
    String? error;
    if (ssid.isEmpty || ssid.length > 32 || !_plain(ssid)) {
      error = l.wifiNameRule;
    } else if (password.length < 8 ||
        password.length > 63 ||
        !_plain(password)) {
      error = l.wifiPasswordRule;
    }
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    Navigator.pop(context, (ssid, password));
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AlertDialog(
      title: Text(l.wifiDialogTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _ssid,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(labelText: l.wifiName),
          ),
          TextField(
            controller: _password,
            obscureText: !_show,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: l.newPassword,
              suffixIcon: IconButton(
                tooltip: _show ? l.hidePassword : l.showPassword,
                onPressed: () => setState(() => _show = !_show),
                icon: Icon(_show ? Icons.visibility_off : Icons.visibility),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _error ?? l.wifiPasswordWarning,
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
          child: Text(l.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l.change)),
      ],
    );
  }
}
