import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/lg_tv_device.dart';

/// Persists paired TVs (and their SSAP client-keys) locally using
/// `shared_preferences`.
///
/// Everything is stored under a single JSON object keyed by TV IP:
/// ```json
/// {
///   "192.168.1.42": {
///     "ip": "192.168.1.42",
///     "name": "Living Room TV",
///     "clientKey": "abc123...",
///     "lastConnectedAt": "2024-06-01T12:00:00.000Z"
///   }
/// }
/// ```
class PairedTvStore {
  static const String _prefsKey = 'paired_tvs';

  /// Saves (or updates) a paired TV. The [lastConnectedAt] timestamp is set to
  /// now unless one is already present on the device.
  Future<void> savePairedTv(LgTvDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _readAll(prefs);
    final toSave = device.lastConnectedAt == null
        ? device.copyWith(lastConnectedAt: DateTime.now().toIso8601String())
        : device;
    all[device.ip] = toSave;
    await _writeAll(prefs, all);
  }

  /// Updates only the `lastConnectedAt` timestamp for an already-stored TV.
  /// No-op if the TV isn't stored yet.
  Future<void> touchLastConnected(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _readAll(prefs);
    final existing = all[ip];
    if (existing == null) return;
    all[ip] = existing.copyWith(
      lastConnectedAt: DateTime.now().toIso8601String(),
    );
    await _writeAll(prefs, all);
  }

  /// Returns the stored TV for [ip], or null if none is paired.
  Future<LgTvDevice?> getPairedTv(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _readAll(prefs);
    return all[ip];
  }

  /// Returns all stored TVs (unordered).
  Future<List<LgTvDevice>> getAllPairedTvs() async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _readAll(prefs);
    return all.values.toList();
  }

  /// Removes the stored TV for [ip], if present.
  Future<void> removePairedTv(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    final all = await _readAll(prefs);
    all.remove(ip);
    await _writeAll(prefs, all);
  }

  /// Reads and decodes the full map. Returns an empty map on missing or
  /// corrupt data (corrupt data is treated as "nothing stored" rather than
  /// throwing, so a bad write can't brick the app).
  Future<Map<String, LgTvDevice>> _readAll(SharedPreferences prefs) async {
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map(
        (ip, json) => MapEntry(
          ip,
          LgTvDevice.fromJson(json as Map<String, dynamic>),
        ),
      );
    } on Object {
      return {};
    }
  }

  Future<void> _writeAll(
    SharedPreferences prefs,
    Map<String, LgTvDevice> all,
  ) async {
    final encoded = jsonEncode(
      all.map((ip, device) => MapEntry(ip, device.toJson())),
    );
    await prefs.setString(_prefsKey, encoded);
  }
}
