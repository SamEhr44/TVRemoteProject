import 'dart:io';
import 'dart:typed_data';

/// Sends Wake-on-LAN "magic packets" to power an LG TV back on over the LAN.
///
/// A magic packet is a UDP broadcast containing six `0xFF` bytes followed by
/// the target's 6-byte MAC repeated 16 times (102 bytes total). For this to
/// work the TV must have a WoL-capable setting enabled (e.g. LG's
/// "Mobile TV On" / "Turn on via Wi-Fi"), and the phone must be on the same
/// LAN/subnet (broadcasts don't cross routers).
class WakeOnLanService {
  /// Sends a magic packet for [mac].
  ///
  /// The packet is broadcast to the limited broadcast address and, when
  /// [deviceIp] is supplied, to that IP's /24 subnet broadcast (e.g.
  /// `192.168.1.42` -> `192.168.1.255`), which some routers handle more
  /// reliably. Sent to the common WoL ports 9 and 7.
  ///
  /// Throws [FormatException] if [mac] is not a valid MAC address.
  Future<void> wake(String mac, {String? deviceIp}) async {
    final packet = _buildMagicPacket(mac);

    final targets = <String>{'255.255.255.255'};
    final subnet = _subnetBroadcast(deviceIp);
    if (subnet != null) targets.add(subnet);

    RawDatagramSocket? socket;
    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      for (final target in targets) {
        final address = InternetAddress(target);
        for (final port in const [9, 7]) {
          socket.send(packet, address, port);
        }
      }
    } finally {
      socket?.close();
    }
  }

  /// Builds the 102-byte magic packet for [mac].
  Uint8List _buildMagicPacket(String mac) {
    final macBytes = _parseMac(mac);
    final packet = Uint8List(6 + 16 * 6);
    for (var i = 0; i < 6; i++) {
      packet[i] = 0xFF;
    }
    for (var rep = 0; rep < 16; rep++) {
      packet.setRange(6 + rep * 6, 6 + rep * 6 + 6, macBytes);
    }
    return packet;
  }

  /// Parses `AA:BB:CC:DD:EE:FF` or `AA-BB-...` into 6 bytes.
  Uint8List _parseMac(String mac) {
    final parts = mac.trim().split(RegExp(r'[:-]'));
    if (parts.length != 6) {
      throw FormatException('Invalid MAC address: $mac');
    }
    final bytes = Uint8List(6);
    for (var i = 0; i < 6; i++) {
      final value = int.tryParse(parts[i], radix: 16);
      if (value == null || value < 0 || value > 0xFF) {
        throw FormatException('Invalid MAC address: $mac');
      }
      bytes[i] = value;
    }
    return bytes;
  }

  /// Returns the /24 subnet broadcast for an IPv4 [ip], or null if unparseable.
  String? _subnetBroadcast(String? ip) {
    if (ip == null) return null;
    final octets = ip.split('.');
    if (octets.length != 4) return null;
    if (octets.any((o) => int.tryParse(o) == null)) return null;
    return '${octets[0]}.${octets[1]}.${octets[2]}.255';
  }
}
