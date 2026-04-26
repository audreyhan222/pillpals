import 'dart:convert';
import 'dart:io';

/// Minimal NDJSON debug logger (DEBUG MODE session: 5fa432).
/// Do not log secrets/PII.
class DebugLog {
  static const String _path = '/Users/skirio/Documents/GitHub/pillpals/.cursor/debug-5fa432.log';
  static const String _sessionId = '5fa432';

  static void write({
    required String runId,
    required String hypothesisId,
    required String location,
    required String message,
    Map<String, Object?> data = const {},
  }) {
    try {
      final payload = <String, Object?>{
        'sessionId': _sessionId,
        'runId': runId,
        'hypothesisId': hypothesisId,
        'location': location,
        'message': message,
        'data': data,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };
      File(_path).writeAsStringSync('${jsonEncode(payload)}\n', mode: FileMode.append);
    } catch (_) {
      // ignore
    }
  }
}

