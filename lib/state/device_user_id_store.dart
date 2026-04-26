import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';

/// Minimal stand-in for "current user id" until Firebase Auth is wired up.
///
/// This gives us a stable Firestore document namespace per installed app.
class DeviceUserIdStore {
  static const _key = 'device_user_id_v1';
  static const _uuid = Uuid();
  static const _storage = FlutterSecureStorage();

  static Future<String> getOrCreate() async {
    final existing = await _storage.read(key: _key);
    if (existing != null && existing.trim().isNotEmpty) return existing.trim();
    final id = _uuid.v4();
    await _storage.write(key: _key, value: id);
    return id;
  }

  /// Replace the stored id (e.g. set to `FDB2EMND` to enable the red 8:55 AM today’s-pill demo on the dashboard).
  static Future<void> writeId(String id) async {
    final t = id.trim();
    if (t.isEmpty) return;
    await _storage.write(key: _key, value: t);
  }
}

