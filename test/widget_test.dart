import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lg_webos_wifi_remote/main.dart';

void main() {
  testWidgets('App boots to the scan screen', (WidgetTester tester) async {
    await tester.pumpWidget(const LgRemoteApp());
    await tester.pump();

    // Title and primary scan action are present.
    expect(find.text('LG webOS Wi-Fi Remote'), findsOneWidget);
    expect(find.byType(FilledButton), findsWidgets);
    expect(find.text('Scan for LG TVs'), findsOneWidget);

    // Empty state guidance is shown before any scan finds a TV.
    expect(find.textContaining('same Wi-Fi network'), findsOneWidget);
  });
}
