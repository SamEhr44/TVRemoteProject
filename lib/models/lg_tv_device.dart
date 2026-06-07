/// Represents a single LG webOS TV, either freshly discovered on the network
/// or restored from local storage (a previously paired TV).
///
/// Discovery populates [ip], [name], [location], [server], [st] and [usn].
/// Pairing/storage additionally populate [clientKey] and [lastConnectedAt].
class LgTvDevice {
  /// The TV's IPv4 address on the local network, e.g. `192.168.1.42`.
  final String ip;

  /// A human-friendly name. Falls back to the IP if no friendly name was found.
  final String name;

  /// The SSDP `LOCATION` header (device description XML URL), if provided.
  final String? location;

  /// The SSDP `SERVER` header, if provided (often contains "WebOS").
  final String? server;

  /// The SSDP `ST` (search target) header that matched this device.
  final String? st;

  /// The SSDP `USN` (unique service name) header, if provided.
  final String? usn;

  /// The SSAP client-key returned by the TV after a successful pairing.
  /// Null until the user has paired with this TV at least once.
  final String? clientKey;

  /// The TV's network MAC address (learned while connected), used to send a
  /// Wake-on-LAN magic packet to power the TV back on. Null until learned.
  final String? macAddress;

  /// ISO-8601 timestamp of the last successful connection, if any.
  final String? lastConnectedAt;

  const LgTvDevice({
    required this.ip,
    required this.name,
    this.location,
    this.server,
    this.st,
    this.usn,
    this.clientKey,
    this.macAddress,
    this.lastConnectedAt,
  });

  /// Whether we already hold a stored client-key for this TV (skips the
  /// on-TV approval prompt on reconnect).
  bool get isPaired => clientKey != null && clientKey!.isNotEmpty;

  /// Returns a copy with selected fields overridden.
  LgTvDevice copyWith({
    String? ip,
    String? name,
    String? location,
    String? server,
    String? st,
    String? usn,
    String? clientKey,
    String? macAddress,
    String? lastConnectedAt,
  }) {
    return LgTvDevice(
      ip: ip ?? this.ip,
      name: name ?? this.name,
      location: location ?? this.location,
      server: server ?? this.server,
      st: st ?? this.st,
      usn: usn ?? this.usn,
      clientKey: clientKey ?? this.clientKey,
      macAddress: macAddress ?? this.macAddress,
      lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
    );
  }

  /// JSON shape used by [PairedTvStore]. Discovery-only fields are kept so a
  /// stored TV can still be displayed without re-running discovery.
  Map<String, dynamic> toJson() => {
    'ip': ip,
    'name': name,
    'location': location,
    'server': server,
    'st': st,
    'usn': usn,
    'clientKey': clientKey,
    'macAddress': macAddress,
    'lastConnectedAt': lastConnectedAt,
  };

  factory LgTvDevice.fromJson(Map<String, dynamic> json) {
    return LgTvDevice(
      ip: json['ip'] as String,
      name: (json['name'] as String?) ?? json['ip'] as String,
      location: json['location'] as String?,
      server: json['server'] as String?,
      st: json['st'] as String?,
      usn: json['usn'] as String?,
      clientKey: json['clientKey'] as String?,
      macAddress: json['macAddress'] as String?,
      lastConnectedAt: json['lastConnectedAt'] as String?,
    );
  }

  /// Two devices are considered the same TV when they share an IP address.
  @override
  bool operator ==(Object other) => other is LgTvDevice && other.ip == ip;

  @override
  int get hashCode => ip.hashCode;

  @override
  String toString() => 'LgTvDevice(name: $name, ip: $ip, paired: $isPaired)';
}
