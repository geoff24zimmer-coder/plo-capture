import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'db/hand_store.dart';
import 'screens/landing_screen.dart';
import 'screens/replayer_screen.dart';
import 'share_link.dart';

void main() {
  // In the browser, route sqflite through the IndexedDB/wasm web factory so
  // hand_store persists hands. Native builds keep the default factory. The
  // shared-worker variant bundles the correct sqlite3 wasm bindings (the
  // no-web-worker path mis-wires the wasm `env` imports).
  if (kIsWeb) {
    databaseFactory = databaseFactoryFfiWeb;
  }
  // Prime the DB in the background (during the splash) so the first session
  // create / hand save is instant rather than waiting on lazy wasm/IndexedDB init.
  HandStore.instance.warmUp();
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
          seedColor: const Color(0xFF10B981), // emerald accent (mirrors solver)
          brightness: Brightness.dark,
          surface: const Color(0xFF151917),
        ),
        scaffoldBackgroundColor: const Color(0xFF0C0F0E),
        sliderTheme: const SliderThemeData(showValueIndicator: ShowValueIndicator.always),
      ),
      home: _home(),
    );
  }

  /// If the app was opened via a share link (`…/#/r?h=<token>`), drop straight
  /// into the shared replay; otherwise show the landing screen. A link we can't
  /// decode gets a friendly error rather than a blank app.
  Widget _home() {
    final link = parseShareLink();
    if (!link.isShare) return const LandingScreen();
    if (link.hand == null) return const _BrokenLinkScreen();
    return ReplayerScreen(handJson: link.hand, shared: true);
  }
}

/// Shown when a `#/r?h=…` link is present but the token can't be decoded
/// (corrupted in transit, truncated, or from an incompatible build).
class _BrokenLinkScreen extends StatelessWidget {
  const _BrokenLinkScreen();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.link_off,
                  size: 48, color: Colors.white.withValues(alpha: 0.4)),
              const SizedBox(height: 16),
              const Text("This replay link couldn't be read",
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                'It may be incomplete or from an older version of the app.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => Navigator.pushReplacement(context,
                    MaterialPageRoute(builder: (_) => const LandingScreen())),
                child: const Text('Open The PLO Show'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
