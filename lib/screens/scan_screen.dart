import 'dart:async';

import 'package:flutter/material.dart';

import '../models/lg_tv_device.dart';
import '../services/lg_webos_service.dart';
import '../services/paired_tv_store.dart';
import '../services/ssdp_discovery_service.dart';
import '../services/wake_on_lan_service.dart';
import 'pairing_screen.dart';

/// First screen: scans the local network for LG webOS TVs and lists them,
/// alongside any previously paired TVs for quick reconnect.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final SsdpDiscoveryService _discovery = SsdpDiscoveryService();
  final PairedTvStore _store = PairedTvStore();

  // One shared connection service for the whole session.
  final LgWebOsService _lg = LgWebOsService();
  final WakeOnLanService _wol = WakeOnLanService();

  final List<LgTvDevice> _discovered = [];
  List<LgTvDevice> _paired = [];
  StreamSubscription<LgTvDevice>? _scanSub;
  bool _isScanning = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPaired();
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    _lg.dispose();
    super.dispose();
  }

  Future<void> _loadPaired() async {
    final paired = await _store.getAllPairedTvs();
    if (!mounted) return;
    setState(() => _paired = paired);
  }

  void _startScan() {
    _scanSub?.cancel();
    setState(() {
      _isScanning = true;
      _error = null;
      _discovered.clear();
    });

    _scanSub = _discovery.discover().listen(
      (device) {
        setState(() {
          // Replace any earlier entry for the same IP (e.g. when a nicer
          // friendly name arrives after the initial detection).
          _discovered
            ..removeWhere((d) => d.ip == device.ip)
            ..add(device);
        });
      },
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _error = e.toString();
          _isScanning = false;
        });
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _isScanning = false);
      },
    );
  }

  Future<void> _openDevice(LgTvDevice device) async {
    // Merge in a stored client-key if we've paired with this TV before.
    final stored = await _store.getPairedTv(device.ip);
    final merged = stored != null
        ? device.copyWith(
            clientKey: stored.clientKey,
            macAddress: stored.macAddress,
            name: device.name.startsWith('LG ') ? stored.name : device.name,
          )
        : device;

    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PairingScreen(lg: _lg, store: _store, device: merged),
      ),
    );
    // Refresh paired list when returning (a new pairing may have been saved).
    await _loadPaired();
  }

  /// Sends a Wake-on-LAN magic packet to power a previously-paired TV back on.
  Future<void> _wake(LgTvDevice device) async {
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final mac = device.macAddress;
    if (mac == null || mac.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Connect once while the TV is on to enable Wake-on-LAN.',
          ),
        ),
      );
      return;
    }
    try {
      await _wol.wake(mac, deviceIp: device.ip);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Wake signal sent to ${device.name}. '
            'Give the TV a few seconds…',
          ),
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
      appBar: AppBar(title: const Text('LG webOS Wi-Fi Remote')),
      body: RefreshIndicator(
        onRefresh: () async => _startScan(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _ScanButton(isScanning: _isScanning, onPressed: _startScan),
            if (_isScanning) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              Text(
                'Searching for LG TVs on your Wi-Fi…',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              _ErrorBanner(message: _error!),
            ],
            if (_paired.isNotEmpty) ...[
              const SizedBox(height: 24),
              _SectionHeader('Previously paired'),
              ..._paired.map(
                (tv) => _DeviceTile(
                  device: tv,
                  paired: true,
                  onTap: () => _openDevice(tv),
                  onWake: () => _wake(tv),
                ),
              ),
            ],
            const SizedBox(height: 24),
            _SectionHeader('Discovered'),
            ..._buildDiscovered(),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildDiscovered() {
    if (_discovered.isEmpty) {
      return [_EmptyState(isScanning: _isScanning)];
    }
    final pairedIps = _paired.map((e) => e.ip).toSet();
    return _discovered
        .map(
          (device) => _DeviceTile(
            device: device,
            paired: pairedIps.contains(device.ip),
            onTap: () => _openDevice(device),
          ),
        )
        .toList();
  }
}

class _ScanButton extends StatelessWidget {
  const _ScanButton({required this.isScanning, required this.onPressed});

  final bool isScanning;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: isScanning ? null : onPressed,
      icon: isScanning
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.wifi_find),
      label: Text(isScanning ? 'Scanning…' : 'Scan for LG TVs'),
      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.device,
    required this.paired,
    required this.onTap,
    this.onWake,
  });

  final LgTvDevice device;
  final bool paired;
  final VoidCallback onTap;

  /// When provided, shows a Wake-on-LAN power button (for paired TVs).
  final VoidCallback? onWake;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const CircleAvatar(child: Icon(Icons.tv)),
        title: Text(device.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(device.ip),
            if (device.location != null)
              Text(
                device.location!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
        isThreeLine: device.location != null,
        trailing: paired
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onWake != null)
                    IconButton(
                      tooltip: 'Power on (Wake-on-LAN)',
                      icon: const Icon(Icons.power_settings_new),
                      onPressed: onWake,
                    ),
                  const Chip(
                    label: Text('Paired'),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              )
            : const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.isScanning});
  final bool isScanning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(Icons.tv_off, size: 40, color: theme.colorScheme.outline),
          const SizedBox(height: 12),
          Text(
            isScanning ? 'Looking for TVs…' : 'No LG TVs found yet',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Make sure your phone and LG TV are on the same Wi-Fi network and '
            'mobile control is enabled on the TV.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: theme.colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
