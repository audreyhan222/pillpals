import 'package:dio/dio.dart';

class ApiClient {
  ApiClient({required String baseUrl, String? token})
      : dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            // The backend can take a bit (OCR → network → LLM), and iOS devices
            // on Wi‑Fi may have slower initial connects to a dev machine.
            connectTimeout: const Duration(seconds: 25),
            receiveTimeout: const Duration(seconds: 60),
            headers: token != null ? {'Authorization': 'Bearer $token'} : null,
          ),
        );

  final Dio dio;

  ApiClient withToken(String? token) {
    final headers = Map<String, dynamic>.from(dio.options.headers);
    if (token == null) {
      headers.remove('Authorization');
    } else {
      headers['Authorization'] = 'Bearer $token';
    }
    dio.options.headers = headers;
    return this;
  }
}

