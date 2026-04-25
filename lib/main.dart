import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/landing_page.dart';
import 'theme/app_colors.dart';

void main() async {
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
  runApp(const MainApp());
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PillPal',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.deepBlue,
          brightness: Brightness.light,
        ),
        fontFamily: 'Segoe UI',
        textTheme: const TextTheme(
          displayLarge: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: AppColors.darkText,
          ),
          displaySmall: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.darkText,
          ),
          titleLarge: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w600,
            color: AppColors.darkText,
          ),
          titleMedium: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: AppColors.darkText,
          ),
          bodyLarge: TextStyle(
            fontSize: 16,
            color: AppColors.mediumText,
          ),
          bodyMedium: TextStyle(
            fontSize: 14,
            color: AppColors.mediumText,
          ),
          bodySmall: TextStyle(
            fontSize: 12,
            color: AppColors.mediumText,
          ),
        ),
      ),
      home: const LandingPage(),
    );
  }
}
