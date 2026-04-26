import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SessionStore extends ChangeNotifier {
  static const _tokenKey = 'access_token';
  static const _roleKey = 'user_role';
  static const _usernameKey = 'session_username';

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  String? _token;
  String? get token => _token;
  bool get isAuthed => _token != null && _token!.isNotEmpty;

  String? _role;
  String? get role => _role;
  bool get hasRole => _role != null && _role!.isNotEmpty;

  String? _username;
  String? get username => _username;

  bool _bootstrapped = false;
  bool get bootstrapped => _bootstrapped;

  Future<void> bootstrap() async {
    _token = await _storage.read(key: _tokenKey);
    _role = await _storage.read(key: _roleKey);
    _username = await _storage.read(key: _usernameKey);
    _bootstrapped = true;
    notifyListeners();
  }

  Future<void> setToken(String token) async {
    _token = token;
    await _storage.write(key: _tokenKey, value: token);
    notifyListeners();
  }

  Future<void> setRole(String role) async {
    _role = role;
    await _storage.write(key: _roleKey, value: role);
    notifyListeners();
  }

  Future<void> setUsername(String username) async {
    final t = username.trim();
    _username = t.isEmpty ? null : t;
    if (_username == null) {
      await _storage.delete(key: _usernameKey);
    } else {
      await _storage.write(key: _usernameKey, value: _username);
    }
    notifyListeners();
  }

  Future<void> clearRole() async {
    _role = null;
    await _storage.delete(key: _roleKey);
    notifyListeners();
  }

  Future<void> logout() async {
    _token = null;
    await _storage.delete(key: _tokenKey);
    _role = null;
    await _storage.delete(key: _roleKey);
    _username = null;
    await _storage.delete(key: _usernameKey);
    notifyListeners();
  }
}

