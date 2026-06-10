import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'screens/landing_screen.dart';

void main() {
  // In the browser, route sqflite through the IndexedDB/wasm web factory so
  // hand_store persists hands. Native builds keep the default factory. The
  // shared-worker variant bundles the correct sqlite3 wasm bindings (the
  // no-web-worker path mis-wires the wasm `env` imports).
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }
  runApp(const PloCaptureApp());
}

class PloCaptureApp extends StatelessWidget {
  const PloCaptureApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The PLO Show',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1D9E75),
          brightness: Brightness.dark,
          surface: const Color(0xFF151917),
        ),
        scaffoldBackgroundColor: const Color(0xFF0C0F0E),
        sliderTheme: const SliderThemeData(showValueIndicator: ShowValueIndicator.always),
      ),
      home: const LandingScreen(),
    );
  }
}
