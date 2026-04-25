import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Resolves the backend base URL. Precedence: `--dart-define=API_BASE_URL=...`
/// (non-empty) → [`.env` asset](`API_BASE_URL`) → `http://127.0.0.1:8000`.
class AppConfig {
  static String get apiBaseUrl {
    const fromDefine =
        String.fromEnvironment('API_BASE_URL', defaultValue: '');
    if (fromDefine.trim().isNotEmpty) {
      return fromDefine.trim();
    }
    try {
      final fromDot = dotenv.env['API_BASE_URL']?.trim();
      if (fromDot != null && fromDot.isNotEmpty) {
        return fromDot;
      }
    } catch (_) {
      // dotenv not loaded or not available
    }
    return 'http://127.0.0.1:8000';
  }
}

