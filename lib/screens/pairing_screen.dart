import 'package:flutter/material.dart';

import '../models/lg_tv_device.dart';
import '../services/lg_webos_service.dart';
import '../services/paired_tv_store.dart';
import 'remote_screen.dart';

/// Connects to the selected TV and walks the user through pairing.
///
/// If the device already has a stored client-key, the TV should register
/// silently and we go straight to the remote. Otherwise the TV shows an
/// on-screen prompt that the user must accept.
class PairingScreen extends StatefulWidget {
  const PairingScreen({
    super.key,
    required this.lg,
    required this.store,
    required this.device,
  });

  final LgWebOsService lg;
  final PairedTvStore store;
  final LgTvDevice device;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _startPairing();
  }

  @override
  void dispose() {
    // Detach listeners only; the shared service keeps the connection alive so
    // the remote screen can use it.
    super.dispose();
  }

  Future<void> _startPairing() async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      final clientKey = await widget.lg.connectAndRegister(
        ip: widget.device.ip,
        clientKey: widget.device.clientKey,
      );

      // Best-effort: learn the TV's MAC so we can Wake-on-LAN it later.
      String? mac;
      try {
        mac = await widget.lg.fetchMacAddress();
      } catch (_) {
        // Non-fatal — wake just stays unavailable until we learn the MAC.
      }

      // Persist the (possibly new) client-key for future silent reconnects.
      final paired = widget.device.copyWith(
        clientKey: clientKey,
        macAddress: mac,
        lastConnectedAt: DateTime.now().toIso8601String(),
      );
      await widget.store.savePairedTv(paired);

      if (!mounted) return;
      // Replace this screen with the remote so Back returns to the scan list.
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              RemoteScreen(lg: widget.lg, store: widget.store, device: paired),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _busy = false;
      });
    }
  }

  Future<void> _cancel() async {
    await widget.lg.disconnect();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text('Pair with ${widget.device.name}')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.tv, size: 32),
                title: Text(widget.device.name),
                subtitle: Text(widget.device.ip),
              ),
            ),
            const SizedBox(height: 32),
            Expanded(
              child: Center(
                child: _error != null
                    ? _PairingError(message: _error!)
                    : _PairingProgress(lg: widget.lg),
              ),
            ),
            if (_error != null) ...[
              FilledButton.icon(
                onPressed: _busy ? null : _startPairing,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              const SizedBox(height: 12),
            ],
            OutlinedButton(
              onPressed: _cancel,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Cancel'),
            ),
            const SizedBox(height: 8),
            Text(
              'Tip: enable "Mobile TV On" / LG Connect Apps on the TV if pairing '
              'never prompts.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Live pairing progress driven by the service's pairing/status notifiers.
class _PairingProgress extends StatelessWidget {
  const _PairingProgress({required this.lg});
  final LgWebOsService lg;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<LgPairingState>(
      valueListenable: lg.pairingState,
      builder: (context, state, _) {
        final promptShown = state == LgPairingState.promptShown;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Icon(
              promptShown ? Icons.touch_app : Icons.cast_connected,
              size: 48,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(height: 16),
            Text(
              promptShown
                  ? 'Accept the pairing request on your LG TV.'
                  : 'Connecting to the TV…',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<String?>(
              valueListenable: lg.statusMessage,
              builder: (context, message, _) => Text(
                message ?? '',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _PairingError extends StatelessWidget {
  const _PairingError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
        const SizedBox(height: 16),
        Text('Pairing failed', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}
