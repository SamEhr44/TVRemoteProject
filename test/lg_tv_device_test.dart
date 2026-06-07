import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lg_webos_wifi_remote/models/lg_tv_device.dart';
import 'package:lg_webos_wifi_remote/services/paired_tv_store.dart';

void main() {
  group('LgTvDevice', () {
    test('JSON round-trips all fields', () {
      const device = LgTvDevice(
        ip: '192.168.1.42',
        name: 'Living Room TV',
        location: 'http://192.168.1.42:1234/desc.xml',
        server: 'WebOS/1.0 UPnP/1.0',
        st: 'urn:lge-com:service:webos-second-screen:1',
        usn: 'uuid:abc::urn',
        clientKey: 'key-123',
        lastConnectedAt: '2024-06-01T12:00:00.000Z',
      );

      final restored = LgTvDevice.fromJson(device.toJson());

      expect(restored.ip, device.ip);
      expect(restored.name, device.name);
      expect(restored.location, device.location);
      expect(restored.clientKey, device.clientKey);
      expect(restored.isPaired, isTrue);
      expect(restored, device); // identity is by IP
    });

    test('isPaired is false without a client key', () {
      const device = LgTvDevice(ip: '10.0.0.5', name: 'TV');
      expect(device.isPaired, isFalse);
    });
  });

  group('PairedTvStore', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('save, get, list, and remove', () async {
      final store = PairedTvStore();
      const tv = LgTvDevice(
        ip: '192.168.1.50',
        name: 'Bedroom TV',
        clientKey: 'abc',
      );

      await store.savePairedTv(tv);

      final fetched = await store.getPairedTv('192.168.1.50');
      expect(fetched, isNotNull);
      expect(fetched!.clientKey, 'abc');
      expect(fetched.lastConnectedAt, isNotNull); // stamped on save

      expect((await store.getAllPairedTvs()).length, 1);

      await store.removePairedTv('192.168.1.50');
      expect(await store.getPairedTv('192.168.1.50'), isNull);
    });
  });
}
