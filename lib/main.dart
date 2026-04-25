import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // If Firebase isn't configured for the current platform (e.g. web),
  // don't crash the whole app before any UI can render.
  try {
    if (kIsWeb) {
      // FlutterFire requires web options; if they're missing, initialization throws.
      // We still allow the app UI to load for local development.
      await Firebase.initializeApp();
    } else {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }
  runApp(const PillPalsApp());
}
