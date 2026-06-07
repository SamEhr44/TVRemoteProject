import 'package:flutter/material.dart';

import 'screens/scan_screen.dart';

void main() {
  runApp(const LgRemoteApp());
}

/// Root of the LG webOS Wi-Fi Remote app.
class LgRemoteApp extends StatelessWidget {
  const LgRemoteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LG webOS Wi-Fi Remote',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFA50034)),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFA50034),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const ScanScreen(),
    );
  }
}
