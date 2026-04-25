import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/app_config.dart';

class ApiConfigStore extends ChangeNotifier {
  static const _baseUrlKey = 'api_base_url';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String _baseUrl = AppConfig.apiBaseUrl;
  String get baseUrl => _baseUrl;

  bool _bootstrapped = false;
  bool get bootstrapped => _bootstrapped;

  Future<void> bootstrap() async {
    final fromConfig = AppConfig.apiBaseUrl;
    final stored = await _storage.read(key: _baseUrlKey);
    if (stored == null || stored.trim().isEmpty) {
      _baseUrl = fromConfig;
    } else {
      final t = stored.trim();
      // A phone cannot reach the Mac at 127.0.0.1; if .env (or build define)
      // was updated to a LAN URL, migrate off the old loopback in secure storage.
      if (_isLoopbackUrl(t) && !_isLoopbackUrl(fromConfig)) {
        _baseUrl = fromConfig;
        await _storage.write(key: _baseUrlKey, value: _baseUrl);
      } else {
        _baseUrl = t;
      }
    }
    _bootstrapped = true;
    notifyListeners();
  }

  static bool _isLoopbackUrl(String url) {
    final s = url.toLowerCase();
    return s.contains('127.0.0.1') || s.contains('localhost');
  }

  Future<void> setBaseUrl(String url) async {
    final trimmed = url.trim();
    _baseUrl = trimmed.isEmpty ? AppConfig.apiBaseUrl : trimmed;
    await _storage.write(key: _baseUrlKey, value: _baseUrl);
    notifyListeners();
  }

  Future<void> resetToDefault() async {
    _baseUrl = AppConfig.apiBaseUrl;
    await _storage.delete(key: _baseUrlKey);
    notifyListeners();
  }
}

