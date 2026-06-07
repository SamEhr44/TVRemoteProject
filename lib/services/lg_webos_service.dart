import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';

/// High-level connection lifecycle exposed to the UI.
enum LgConnectionState { disconnected, connecting, connected, error }

/// Pairing/registration progress exposed to the UI.
enum LgPairingState {
  /// No pairing attempt in progress.
  idle,

  /// Register message sent; waiting for the TV to respond.
  registering,

  /// The TV is showing the on-screen approval prompt — the user must accept.
  promptShown,

  /// Successfully registered; a client-key is available.
  paired,

  /// Registration failed (rejected, timed out, or errored).
  failed,
}

/// Controls a single LG webOS TV over the SSAP WebSocket protocol.
///
/// Connection strategy:
///   1. Try the plaintext socket `ws://<ip>:3000`.
///   2. Fall back to the TLS socket `wss://<ip>:3001` (self-signed cert, so
///      certificate validation is intentionally bypassed for LAN devices).
///
/// After connecting, a `register` message is sent. On a fresh TV the user must
/// accept an on-screen prompt; the TV then returns a `client-key` which is
/// reused on subsequent connections to skip the prompt.
///
/// Directional buttons (Home/Back/arrows/OK) are not plain SSAP requests — they
/// go through LG's *pointer input socket*: a secondary WebSocket whose URL is
/// obtained via an SSAP request. See [sendButton].
class LgWebOsService {
  LgWebOsService({this.commandTimeout = const Duration(seconds: 8)});

  /// How long to wait for a command's response before failing.
  final Duration commandTimeout;

  /// Current connection lifecycle state (listenable for the UI).
  final ValueNotifier<LgConnectionState> connectionState = ValueNotifier(
    LgConnectionState.disconnected,
  );

  /// Current pairing state (listenable for the UI).
  final ValueNotifier<LgPairingState> pairingState = ValueNotifier(
    LgPairingState.idle,
  );

  /// Human-readable status/instruction or last error, for display.
  final ValueNotifier<String?> statusMessage = ValueNotifier<String?>(null);

  IOWebSocketChannel? _channel;
  StreamSubscription<dynamic>? _channelSub;

  // The LG pointer input socket (used for directional/Home/Back/OK buttons).
  IOWebSocketChannel? _inputChannel;

  int _messageId = 0;
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  Completer<String>? _registerCompleter;

  bool get isConnected => connectionState.value == LgConnectionState.connected;

  /// Connects to the TV at [ip] and registers, returning the client-key.
  ///
  /// If [clientKey] is supplied (a previously stored key), the TV should skip
  /// the on-screen prompt and register immediately. Throws on failure with a
  /// human-readable message; also surfaced via [statusMessage].
  ///
  /// [registerTimeout] is generous because a first-time pairing waits for the
  /// user to physically accept the prompt on the TV.
  Future<String> connectAndRegister({
    required String ip,
    String? clientKey,
    Duration registerTimeout = const Duration(seconds: 90),
  }) async {
    await disconnect();
    _setStatus(null);
    connectionState.value = LgConnectionState.connecting;
    pairingState.value = LgPairingState.idle;

    try {
      _channel = await _openChannel(ip);
    } on Object catch (e) {
      connectionState.value = LgConnectionState.error;
      final msg =
          'Could not connect to TV at $ip. '
          'Make sure the TV is on, on the same Wi-Fi, and that mobile/LAN '
          'control is enabled. ($e)';
      _setStatus(msg);
      throw Exception(msg);
    }

    _listen();

    final completer = Completer<String>();
    _registerCompleter = completer;
    pairingState.value = LgPairingState.registering;
    _setStatus('Registering with the TV…');

    _send(_buildRegisterMessage(clientKey));

    return completer.future.timeout(
      registerTimeout,
      onTimeout: () {
        pairingState.value = LgPairingState.failed;
        const msg = 'Pairing timed out. Did you accept the prompt on the TV?';
        _setStatus(msg);
        _registerCompleter = null;
        throw TimeoutException(msg);
      },
    );
  }

  /// Tries `ws://<ip>:3000`, then falls back to `wss://<ip>:3001`.
  Future<IOWebSocketChannel> _openChannel(String ip) async {
    try {
      return await _connectSocket('ws://$ip:3000');
    } on Object {
      // Plaintext failed — try the TLS port (self-signed cert).
      return await _connectSocket('wss://$ip:3001');
    }
  }

  /// Opens a single WebSocket. For `wss://` the LG self-signed certificate is
  /// accepted (these are LAN-local devices, not public endpoints).
  Future<IOWebSocketChannel> _connectSocket(String url) async {
    final httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..badCertificateCallback = (cert, host, port) => true;
    final ws = await WebSocket.connect(
      url,
      customClient: httpClient,
    ).timeout(const Duration(seconds: 6));
    return IOWebSocketChannel(ws);
  }

  void _listen() {
    _channelSub = _channel!.stream.listen(
      (dynamic data) => _handleMessage(data),
      onError: (Object e) => _onChannelClosed('Connection error: $e'),
      onDone: () => _onChannelClosed('Connection closed by TV.'),
      cancelOnError: false,
    );
  }

  void _handleMessage(dynamic data) {
    Map<String, dynamic> message;
    try {
      message = jsonDecode(data as String) as Map<String, dynamic>;
    } on Object {
      return; // Ignore non-JSON frames.
    }

    final type = message['type'] as String?;
    final id = message['id'] as String?;
    final payload = (message['payload'] as Map?)?.cast<String, dynamic>() ?? {};

    // --- Registration handling -------------------------------------------
    if (id == 'register_0') {
      if (type == 'registered') {
        final key = payload['client-key'] as String?;
        pairingState.value = LgPairingState.paired;
        connectionState.value = LgConnectionState.connected;
        _setStatus('Paired and connected.');
        if (key != null && _registerCompleter != null) {
          _registerCompleter!.complete(key);
          _registerCompleter = null;
        }
        return;
      }
      if (type == 'response' && payload['pairingType'] != null) {
        // TV is now displaying the approval prompt.
        pairingState.value = LgPairingState.promptShown;
        _setStatus('Accept the pairing request on your LG TV.');
        return;
      }
      if (type == 'error') {
        pairingState.value = LgPairingState.failed;
        final err = message['error']?.toString() ?? 'Registration rejected.';
        _setStatus('Pairing failed: $err');
        _registerCompleter?.completeError(Exception(err));
        _registerCompleter = null;
        return;
      }
    }

    // --- Generic request/response correlation ----------------------------
    if (id != null && _pending.containsKey(id)) {
      final completer = _pending.remove(id)!;
      if (type == 'error') {
        completer.completeError(
          Exception(message['error']?.toString() ?? 'TV returned an error.'),
        );
      } else {
        completer.complete(payload);
      }
    }
  }

  void _onChannelClosed(String reason) {
    // Fail any in-flight work so callers don't hang.
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.completeError(Exception(reason));
    }
    _pending.clear();
    if (_registerCompleter != null && !_registerCompleter!.isCompleted) {
      _registerCompleter!.completeError(Exception(reason));
      _registerCompleter = null;
    }
    if (connectionState.value != LgConnectionState.disconnected) {
      connectionState.value = LgConnectionState.disconnected;
      _setStatus(reason);
    }
  }

  // --- Generic SSAP request ------------------------------------------------

  /// Sends a generic SSAP request and awaits the TV's response payload.
  ///
  /// Throws [StateError] if not connected, [TimeoutException] if the TV does
  /// not respond within [commandTimeout], or [Exception] if the TV returns an
  /// error frame.
  Future<Map<String, dynamic>> sendRequest(
    String uri, {
    Map<String, dynamic>? payload,
  }) {
    if (_channel == null ||
        connectionState.value != LgConnectionState.connected) {
      throw StateError('Not connected to a TV.');
    }
    final id = 'req_${_messageId++}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    _send({'type': 'request', 'id': id, 'uri': uri, 'payload': ?payload});

    return completer.future.timeout(
      commandTimeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('TV did not respond to $uri.');
      },
    );
  }

  // --- Basic command methods ----------------------------------------------

  Future<void> volumeUp() => sendRequest('ssap://audio/volumeUp');

  Future<void> volumeDown() => sendRequest('ssap://audio/volumeDown');

  Future<void> setMute(bool mute) =>
      sendRequest('ssap://audio/setMute', payload: {'mute': mute});

  Future<void> showToast(String message) => sendRequest(
    'ssap://system.notifications/createToast',
    payload: {'message': message},
  );

  Future<void> powerOff() =>
      sendRequest('ssap://com.webos.service.tvpower/power/turnOff');

  /// Queries the TV's network status and returns the MAC address of the active
  /// interface (preferring the connected one), for Wake-on-LAN. Returns null if
  /// the TV doesn't report a usable MAC.
  Future<String?> fetchMacAddress() async {
    final status = await sendRequest(
      'ssap://com.webos.service.connectionmanager/getStatus',
    );
    final wifi = (status['wifi'] as Map?)?.cast<String, dynamic>();
    final wired = (status['wired'] as Map?)?.cast<String, dynamic>();

    String? macOf(Map<String, dynamic>? iface) {
      final mac = iface?['macAddress'];
      return (mac is String && mac.isNotEmpty) ? mac : null;
    }

    bool isConnected(Map<String, dynamic>? iface) =>
        iface?['state'] == 'connected';

    // Prefer whichever interface is actually connected.
    if (isConnected(wifi)) return macOf(wifi);
    if (isConnected(wired)) return macOf(wired);
    return macOf(wifi) ?? macOf(wired);
  }

  // --- Directional / Home / Back / OK via the pointer input socket --------
  //
  // TODO: Home/Back/arrows/OK are NOT plain SSAP requests. They are delivered
  // over LG's "pointer input socket": we ask the TV for a socket URL via
  // `ssap://com.webos.service.networkinput/getPointerInputSocket`, open that
  // secondary WebSocket, then write line-based `type:button` frames to it.
  // Availability and exact button names can differ across webOS versions; if a
  // given TV does not expose this socket, [sendButton] throws a clear error
  // rather than failing silently.

  Future<void> home() => sendButton('HOME');
  Future<void> back() => sendButton('BACK');
  Future<void> up() => sendButton('UP');
  Future<void> down() => sendButton('DOWN');
  Future<void> left() => sendButton('LEFT');
  Future<void> right() => sendButton('RIGHT');

  /// OK/Enter. webOS uses the `ENTER` button name for the center/select key.
  Future<void> ok() => sendButton('ENTER');

  /// Sends a named button over the pointer input socket, lazily establishing
  /// that socket on first use.
  Future<void> sendButton(String name) async {
    await _ensureInputSocket();
    // Pointer-socket frames are newline-delimited and end with a blank line.
    _inputChannel!.sink.add('type:button\nname:$name\n\n');
  }

  /// Requests the pointer input socket URL from the TV and connects to it.
  Future<void> _ensureInputSocket() async {
    if (_inputChannel != null) return;
    final Map<String, dynamic> response;
    try {
      response = await sendRequest(
        'ssap://com.webos.service.networkinput/getPointerInputSocket',
      );
    } on Object catch (e) {
      throw Exception(
        'This TV did not provide a directional input socket '
        '(may vary by webOS version): $e',
      );
    }
    final socketPath = response['socketPath'] as String?;
    if (socketPath == null || socketPath.isEmpty) {
      throw Exception(
        'TV did not return a pointer input socket path. Directional buttons '
        'may be unsupported on this webOS version.',
      );
    }
    try {
      _inputChannel = await _connectSocket(socketPath);
      // Drain incoming frames; we only write to this socket.
      _inputChannel!.stream.listen(
        (_) {},
        onError: (_) => _inputChannel = null,
        onDone: () => _inputChannel = null,
        cancelOnError: false,
      );
    } on Object catch (e) {
      _inputChannel = null;
      throw Exception('Could not open the TV input socket: $e');
    }
  }

  // --- Lifecycle -----------------------------------------------------------

  /// Closes all sockets and resets state.
  Future<void> disconnect() async {
    await _channelSub?.cancel();
    _channelSub = null;
    await _inputChannel?.sink.close();
    _inputChannel = null;
    await _channel?.sink.close();
    _channel = null;
    _pending.clear();
    _registerCompleter = null;
    if (connectionState.value != LgConnectionState.disconnected) {
      connectionState.value = LgConnectionState.disconnected;
    }
    pairingState.value = LgPairingState.idle;
  }

  /// Releases listenable resources. Call when the service is no longer needed.
  void dispose() {
    disconnect();
    connectionState.dispose();
    pairingState.dispose();
    statusMessage.dispose();
  }

  // --- Internals -----------------------------------------------------------

  void _send(Map<String, dynamic> message) {
    _channel?.sink.add(jsonEncode(message));
  }

  void _setStatus(String? message) => statusMessage.value = message;

  /// Builds the SSAP `register` message, embedding [clientKey] when present so
  /// a known TV skips the approval prompt.
  Map<String, dynamic> _buildRegisterMessage(String? clientKey) {
    return {
      'type': 'register',
      'id': 'register_0',
      'payload': {
        'pairingType': 'PROMPT',
        if (clientKey != null && clientKey.isNotEmpty) 'client-key': clientKey,
        'manifest': _manifest,
      },
    };
  }

  /// The SSAP manifest declaring requested permissions. Identical permission
  /// lists are required at both the top level and inside `signed`.
  static const Map<String, dynamic> _manifest = {
    'manifestVersion': 1,
    'appVersion': '1.0',
    'signed': {
      'created': '20240601',
      'appId': 'com.example.lg_wifi_remote',
      'vendorId': 'com.example',
      'localizedAppNames': {'': 'LG WiFi Remote'},
      'localizedVendorNames': {'': 'Local Developer'},
      'permissions': _permissions,
    },
    'permissions': _permissions,
    'signatures': <dynamic>[],
  };

  static const List<String> _permissions = [
    'LAUNCH',
    'LAUNCH_WEBAPP',
    'APP_TO_APP',
    'CONTROL_AUDIO',
    'CONTROL_DISPLAY',
    'CONTROL_INPUT_TEXT',
    'CONTROL_MOUSE_AND_KEYBOARD',
    'READ_INSTALLED_APPS',
    'READ_LGE_SDX',
    'READ_NOTIFICATIONS',
    'SEARCH',
    'WRITE_NOTIFICATION_TOAST',
    'CONTROL_POWER',
  ];
}
