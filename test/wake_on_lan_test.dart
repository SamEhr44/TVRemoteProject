import 'package:flutter_test/flutter_test.dart';

import 'package:lg_webos_wifi_remote/services/wake_on_lan_service.dart';

void main() {
  group('WakeOnLanService', () {
    final wol = WakeOnLanService();

    test('rejects a malformed MAC address', () async {
      // The MAC is parsed before any socket work, so this fails fast (no I/O).
      await expectLater(wol.wake('not-a-mac'), throwsA(isA<FormatException>()));
      await expectLater(
        wol.wake('AA:BB:CC:DD:EE'), // too few octets
        throwsA(isA<FormatException>()),
      );
      await expectLater(
        wol.wake('GG:BB:CC:DD:EE:FF'), // non-hex octet
        throwsA(isA<FormatException>()),
      );
    });
  });
}
