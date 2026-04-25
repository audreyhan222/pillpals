import 'package:dio/dio.dart';

class ApiClient {
  ApiClient({required String baseUrl, String? token})
      : dio = Dio(
          BaseOptions(
            baseUrl: baseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 20),
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

