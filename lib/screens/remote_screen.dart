import 'package:flutter/material.dart';

import '../models/lg_tv_device.dart';
import '../services/lg_webos_service.dart';
import '../services/paired_tv_store.dart';
import '../services/wake_on_lan_service.dart';
import '../widgets/remote_button.dart';

/// The working remote. Sends SSAP commands over the shared [LgWebOsService]
/// and reports each command's success/failure via a SnackBar.
class RemoteScreen extends StatefulWidget {
  const RemoteScreen({
    super.key,
    required this.lg,
    required this.store,
    required this.device,
  });

  final LgWebOsService lg;
  final PairedTvStore store;
  final LgTvDevice device;

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  final WakeOnLanService _wol = WakeOnLanService();
  bool _muted = false;
  bool _reconnecting = false;

  /// MAC learned for Wake-on-LAN; seeded from the paired device and refreshed
  /// on each (re)connect.
  late String? _macAddress = widget.device.macAddress;

  /// Runs a command, surfacing success or a readable error via SnackBar.
  Future<void> _run(
    Future<void> Function() action, {
    required String success,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      await action();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(success),
            duration: const Duration(milliseconds: 900),
          ),
        );
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(_friendlyError(e)),
            backgroundColor: errorColor,
          ),
        );
    }
  }

  String _friendlyError(Object e) {
    final text = e.toString().replaceFirst('Exception: ', '');
    return text.isEmpty ? 'Command failed.' : text;
  }

  Future<void> _toggleMute() async {
    final next = !_muted;
    await _run(
      () => widget.lg.setMute(next),
      success: next ? 'Muted' : 'Unmuted',
    );
    if (mounted) setState(() => _muted = next);
  }

  Future<void> _reconnect() async {
    setState(() => _reconnecting = true);
    try {
      final key = await widget.lg.connectAndRegister(
        ip: widget.device.ip,
        clientKey: widget.device.clientKey,
      );
      String? mac;
      try {
        mac = await widget.lg.fetchMacAddress();
      } catch (_) {
        // Keep any previously-known MAC.
      }
      if (mac != null && mounted) setState(() => _macAddress = mac);
      await widget.store.savePairedTv(
        widget.device.copyWith(
          clientKey: key,
          macAddress: mac,
          lastConnectedAt: DateTime.now().toIso8601String(),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_friendlyError(e)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _reconnecting = false);
    }
  }

  Future<void> _disconnect() async {
    await widget.lg.disconnect();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  /// Wake the TV back on (useful right after Power Off, which drops the link).
  Future<void> _wake() async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final mac = _macAddress;
    if (mac == null || mac.isEmpty) return;
    try {
      await _wol.wake(mac, deviceIp: widget.device.ip);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Wake signal sent. Give the TV a few seconds…'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Wake failed: $e'), backgroundColor: errorColor),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.device.name, style: const TextStyle(fontSize: 16)),
            Text(
              widget.device.ip,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w400),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Disconnect',
            icon: const Icon(Icons.logout),
            onPressed: _disconnect,
          ),
        ],
      ),
      body: ValueListenableBuilder<LgConnectionState>(
        valueListenable: widget.lg.connectionState,
        builder: (context, state, _) {
          final connected = state == LgConnectionState.connected;
          return Column(
            children: [
              _ConnectionBar(
                state: state,
                reconnecting: _reconnecting,
                onReconnect: _reconnect,
                onWake: _macAddress != null ? _wake : null,
              ),
              Expanded(
                child: AbsorbPointer(
                  absorbing: !connected,
                  child: Opacity(
                    opacity: connected ? 1 : 0.4,
                    child: _RemotePad(
                      muted: _muted,
                      onPower: () =>
                          _run(widget.lg.powerOff, success: 'Power off sent'),
                      onHome: () => _run(widget.lg.home, success: 'Home'),
                      onBack: () => _run(widget.lg.back, success: 'Back'),
                      onUp: () => _run(widget.lg.up, success: 'Up'),
                      onDown: () => _run(widget.lg.down, success: 'Down'),
                      onLeft: () => _run(widget.lg.left, success: 'Left'),
                      onRight: () => _run(widget.lg.right, success: 'Right'),
                      onOk: () => _run(widget.lg.ok, success: 'OK'),
                      onVolUp: () =>
                          _run(widget.lg.volumeUp, success: 'Volume up'),
                      onVolDown: () =>
                          _run(widget.lg.volumeDown, success: 'Volume down'),
                      onMute: _toggleMute,
                      onToast: () => _run(
                        () => widget.lg.showToast('Hello from LG WiFi Remote!'),
                        success: 'Toast sent to TV',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// The remote button layout: power/home/back row, a D-pad, volume row, toast.
class _RemotePad extends StatelessWidget {
  const _RemotePad({
    required this.muted,
    required this.onPower,
    required this.onHome,
    required this.onBack,
    required this.onUp,
    required this.onDown,
    required this.onLeft,
    required this.onRight,
    required this.onOk,
    required this.onVolUp,
    required this.onVolDown,
    required this.onMute,
    required this.onToast,
  });

  final bool muted;
  final VoidCallback onPower;
  final VoidCallback onHome;
  final VoidCallback onBack;
  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onLeft;
  final VoidCallback onRight;
  final VoidCallback onOk;
  final VoidCallback onVolUp;
  final VoidCallback onVolDown;
  final VoidCallback onMute;
  final VoidCallback onToast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Power / Home / Back
          Row(
            children: [
              Expanded(
                child: RemoteButton(
                  icon: Icons.power_settings_new,
                  label: 'Power',
                  color: scheme.errorContainer,
                  foregroundColor: scheme.onErrorContainer,
                  onPressed: onPower,
                  tooltip: 'Power Off',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: RemoteButton(
                  icon: Icons.home,
                  label: 'Home',
                  onPressed: onHome,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: RemoteButton(
                  icon: Icons.arrow_back,
                  label: 'Back',
                  onPressed: onBack,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          // D-pad
          _DPad(
            onUp: onUp,
            onDown: onDown,
            onLeft: onLeft,
            onRight: onRight,
            onOk: onOk,
          ),
          const SizedBox(height: 24),
          // Volume row
          Row(
            children: [
              Expanded(
                child: RemoteButton(
                  icon: Icons.volume_down,
                  label: 'Vol −',
                  onPressed: onVolDown,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: RemoteButton(
                  icon: muted ? Icons.volume_off : Icons.volume_mute,
                  label: muted ? 'Unmute' : 'Mute',
                  color: muted ? scheme.tertiaryContainer : null,
                  foregroundColor: muted ? scheme.onTertiaryContainer : null,
                  onPressed: onMute,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: RemoteButton(
                  icon: Icons.volume_up,
                  label: 'Vol +',
                  onPressed: onVolUp,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          RemoteButton(
            icon: Icons.notifications_active,
            label: 'Toast test',
            onPressed: onToast,
          ),
        ],
      ),
    );
  }
}

/// A directional cross with a center OK button.
class _DPad extends StatelessWidget {
  const _DPad({
    required this.onUp,
    required this.onDown,
    required this.onLeft,
    required this.onRight,
    required this.onOk,
  });

  final VoidCallback onUp;
  final VoidCallback onDown;
  final VoidCallback onLeft;
  final VoidCallback onRight;
  final VoidCallback onOk;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: 96,
          child: RemoteButton(
            icon: Icons.keyboard_arrow_up,
            onPressed: onUp,
            tooltip: 'Up',
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 96,
              child: RemoteButton(
                icon: Icons.keyboard_arrow_left,
                onPressed: onLeft,
                tooltip: 'Left',
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 96,
              child: RemoteButton(
                icon: Icons.circle,
                label: 'OK',
                color: Theme.of(context).colorScheme.primaryContainer,
                foregroundColor: Theme.of(
                  context,
                ).colorScheme.onPrimaryContainer,
                onPressed: onOk,
                tooltip: 'OK / Enter',
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 96,
              child: RemoteButton(
                icon: Icons.keyboard_arrow_right,
                onPressed: onRight,
                tooltip: 'Right',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: 96,
          child: RemoteButton(
            icon: Icons.keyboard_arrow_down,
            onPressed: onDown,
            tooltip: 'Down',
          ),
        ),
      ],
    );
  }
}

/// Shows current connection state and a reconnect affordance when dropped.
class _ConnectionBar extends StatelessWidget {
  const _ConnectionBar({
    required this.state,
    required this.reconnecting,
    required this.onReconnect,
    this.onWake,
  });

  final LgConnectionState state;
  final bool reconnecting;
  final VoidCallback onReconnect;

  /// Wake-on-LAN action, shown while disconnected when a MAC is known.
  final VoidCallback? onWake;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final connected = state == LgConnectionState.connected;
    if (connected) {
      return Container(
        width: double.infinity,
        color: scheme.primaryContainer,
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle,
              size: 16,
              color: scheme.onPrimaryContainer,
            ),
            const SizedBox(width: 8),
            Text(
              'Connected',
              style: TextStyle(color: scheme.onPrimaryContainer),
            ),
          ],
        ),
      );
    }
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Row(
        children: [
          Icon(Icons.cloud_off, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state == LgConnectionState.connecting
                  ? 'Connecting…'
                  : 'Disconnected',
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          if (onWake != null)
            TextButton.icon(
              onPressed: reconnecting ? null : onWake,
              icon: const Icon(Icons.power_settings_new, size: 18),
              label: const Text('Wake'),
            ),
          TextButton(
            onPressed: reconnecting ? null : onReconnect,
            child: Text(reconnecting ? 'Reconnecting…' : 'Reconnect'),
          ),
        ],
      ),
    );
  }
}
