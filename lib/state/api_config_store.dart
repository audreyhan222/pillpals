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
    final stored = await _storage.read(key: _baseUrlKey);
    _baseUrl = (stored == null || stored.trim().isEmpty)
        ? AppConfig.apiBaseUrl
        : stored.trim();
    _bootstrapped = true;
    notifyListeners();
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

