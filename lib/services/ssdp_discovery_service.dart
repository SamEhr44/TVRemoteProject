import 'dart:async';
import 'dart:io';

import '../models/lg_tv_device.dart';

/// Discovers LG webOS TVs on the local network using SSDP/UPnP.
///
/// The flow is:
///   1. Bind a UDP socket to an ephemeral port on all interfaces.
///   2. Send `M-SEARCH` multicast requests to `239.255.255.250:1900` for
///      several search targets (LG-specific, MediaRenderer, and `ssdp:all`).
///   3. Listen for the unicast HTTP-style responses TVs send back.
///   4. Parse headers, filter for LG/webOS indicators, dedupe by IP, and
///      (best effort) fetch the device-description XML to read a friendly name.
///
/// Discovery is exposed as a [Stream] so the UI can show TVs as they appear
/// rather than waiting for the full timeout.
class SsdpDiscoveryService {
  /// Standard SSDP multicast group address.
  static const String _multicastAddress = '239.255.255.250';

  /// Standard SSDP multicast port.
  static const int _multicastPort = 1900;

  /// Search targets sent in the M-SEARCH `ST` header. The LG-specific target
  /// is most reliable; the others widen the net for varying webOS versions.
  static const List<String> _searchTargets = [
    'urn:lge-com:service:webos-second-screen:1',
    'urn:schemas-upnp-org:device:MediaRenderer:1',
    'ssdp:all',
  ];

  /// Substrings (lowercased) that mark a response as a likely LG/webOS device.
  static const List<String> _lgIndicators = [
    'lge',
    'webos',
    'lg smart tv',
    'lgsmarttv',
  ];

  /// Discovers LG TVs, emitting each unique device once as it is found.
  ///
  /// The returned stream completes after [timeout]. Cancelling the stream
  /// subscription early stops discovery and releases the socket.
  Stream<LgTvDevice> discover({Duration timeout = const Duration(seconds: 6)}) {
    // Tracks IPs already emitted so each TV appears at most once.
    final seenIps = <String>{};
    final controller = StreamController<LgTvDevice>();

    RawDatagramSocket? socket;
    Timer? timeoutTimer;
    Timer? rescanTimer;
    var closed = false;

    Future<void> cleanup() async {
      if (closed) return;
      closed = true;
      timeoutTimer?.cancel();
      rescanTimer?.cancel();
      socket?.close();
      if (!controller.isClosed) {
        await controller.close();
      }
    }

    Future<void> start() async {
      try {
        socket = await RawDatagramSocket.bind(
          InternetAddress.anyIPv4,
          0,
          reuseAddress: true,
        );
        // Allow sending to the multicast/broadcast group.
        socket!.broadcastEnabled = true;
        // Limit how far multicast packets travel; the TV is on the LAN.
        try {
          socket!.multicastHops = 4;
        } on Object {
          // Not fatal — some platforms reject this; discovery still works.
        }

        socket!.listen(
          (event) {
            if (event != RawSocketEvent.read) return;
            final datagram = socket!.receive();
            if (datagram == null) return;
            final device = _parseResponse(
              String.fromCharCodes(datagram.data),
              datagram.address.address,
            );
            if (device == null) return;
            if (seenIps.add(device.ip)) {
              if (!controller.isClosed) controller.add(device);
              // Best-effort: enrich with a friendly name from the device XML.
              _enrichWithFriendlyName(device).then((enriched) {
                if (enriched != null && !controller.isClosed) {
                  controller.add(enriched);
                }
              });
            }
          },
          onError: (Object e) {
            if (!controller.isClosed) controller.addError(e);
          },
        );

        _sendSearches(socket!);
        // Re-send once mid-window; UDP is lossy and some TVs answer slowly.
        rescanTimer = Timer(
          Duration(milliseconds: (timeout.inMilliseconds / 2).round()),
          () {
            if (!closed && socket != null) _sendSearches(socket!);
          },
        );

        timeoutTimer = Timer(timeout, cleanup);
      } on Object catch (e) {
        if (!controller.isClosed) {
          controller.addError('Could not start network discovery: $e');
        }
        await cleanup();
      }
    }

    controller.onListen = start;
    controller.onCancel = cleanup;
    return controller.stream;
  }

  /// Sends one M-SEARCH datagram per search target.
  void _sendSearches(RawDatagramSocket socket) {
    final group = InternetAddress(_multicastAddress);
    for (final st in _searchTargets) {
      final message = _buildMSearch(st);
      try {
        socket.send(message.codeUnits, group, _multicastPort);
      } on Object {
        // Ignore per-target send failures; other targets may still succeed.
      }
    }
  }

  /// Builds an RFC-compliant M-SEARCH request. Lines must be CRLF-terminated
  /// and the message must end with a blank line.
  String _buildMSearch(String searchTarget) {
    return 'M-SEARCH * HTTP/1.1\r\n'
        'HOST: $_multicastAddress:$_multicastPort\r\n'
        'MAN: "ssdp:discover"\r\n'
        'MX: 3\r\n'
        'ST: $searchTarget\r\n'
        '\r\n';
  }

  /// Parses an SSDP response into an [LgTvDevice], or returns null if the
  /// response is malformed or does not look like an LG/webOS device.
  LgTvDevice? _parseResponse(String raw, String senderIp) {
    final lower = raw.toLowerCase();
    if (!_looksLikeLg(lower)) return null;

    final headers = _parseHeaders(raw);
    final location = headers['location'];
    final ip = _extractIp(location) ?? senderIp;
    if (ip.isEmpty) return null;

    return LgTvDevice(
      ip: ip,
      name: _initialName(headers, ip),
      location: location,
      server: headers['server'],
      st: headers['st'],
      usn: headers['usn'],
    );
  }

  /// Returns true when the (lowercased) response text contains an LG/webOS
  /// indicator, or is a MediaRenderer that also mentions LG.
  bool _looksLikeLg(String lowerResponse) {
    for (final indicator in _lgIndicators) {
      if (lowerResponse.contains(indicator)) return true;
    }
    final isMediaRenderer = lowerResponse.contains('mediarenderer');
    final mentionsLg =
        lowerResponse.contains('lg') || lowerResponse.contains('lge');
    return isMediaRenderer && mentionsLg;
  }

  /// Splits an SSDP/HTTP message into a lowercased-key header map.
  Map<String, String> _parseHeaders(String raw) {
    final headers = <String, String>{};
    for (final line in raw.split('\r\n')) {
      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim().toLowerCase();
      final value = line.substring(idx + 1).trim();
      if (key.isNotEmpty) headers[key] = value;
    }
    return headers;
  }

  /// Extracts the host portion of a `LOCATION` URL (the TV's IP).
  String? _extractIp(String? location) {
    if (location == null || location.isEmpty) return null;
    final uri = Uri.tryParse(location);
    if (uri == null || uri.host.isEmpty) return null;
    return uri.host;
  }

  /// Best-effort initial name derived from the SERVER header, falling back to
  /// `LG TV (<ip>)`. A nicer friendly name may arrive later via
  /// [_enrichWithFriendlyName].
  String _initialName(Map<String, String> headers, String ip) {
    final server = headers['server'] ?? '';
    if (server.toLowerCase().contains('webos')) {
      return 'LG webOS TV ($ip)';
    }
    return 'LG TV ($ip)';
  }

  /// Fetches the device-description XML at [device.location] and extracts the
  /// `<friendlyName>` element. Returns an updated device, or null on failure.
  ///
  /// This is intentionally best-effort with a short timeout: discovery works
  /// fine without it, it just yields prettier names when the TV exposes them.
  Future<LgTvDevice?> _enrichWithFriendlyName(LgTvDevice device) async {
    final location = device.location;
    if (location == null || location.isEmpty) return null;
    final uri = Uri.tryParse(location);
    if (uri == null) return null;

    HttpClient? client;
    try {
      client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
      final request = await client.getUrl(uri);
      final response = await request.close().timeout(
        const Duration(seconds: 2),
      );
      final body = await response
          .transform(const SystemEncoding().decoder)
          .join()
          .timeout(const Duration(seconds: 2));
      final friendly = _extractTag(body, 'friendlyName');
      if (friendly == null || friendly.trim().isEmpty) return null;
      return device.copyWith(name: friendly.trim());
    } on Object {
      return null;
    } finally {
      client?.close(force: true);
    }
  }

  /// Minimal XML tag extractor (avoids pulling in an XML parser dependency).
  String? _extractTag(String xml, String tag) {
    final open = '<$tag>';
    final close = '</$tag>';
    final start = xml.indexOf(open);
    if (start < 0) return null;
    final end = xml.indexOf(close, start + open.length);
    if (end < 0) return null;
    return xml.substring(start + open.length, end);
  }
}
