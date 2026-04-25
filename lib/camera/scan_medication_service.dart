import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../config/app_config.dart';

class ScanMedicationAiResult {
  const ScanMedicationAiResult({
    required this.name,
    required this.dosage,
    required this.instructions,
    required this.raw,
  });

  final String name;
  final String dosage;
  final String instructions;
  final Map<String, dynamic> raw;
}

class ScanMedicationService {
  ScanMedicationService({String? token, String? baseUrl})
      : _api = ApiClient(
          baseUrl: (baseUrl == null || baseUrl.trim().isEmpty)
              ? AppConfig.apiBaseUrl
              : baseUrl.trim(),
          token: token,
        );

  final ApiClient _api;

  Future<ScanMedicationAiResult> analyzeText({required String text}) async {
    final res = await _api.dio.post(
      ApiEndpoints.scanMedication,
      data: <String, dynamic>{
        'text': text,
      },
      options: Options(
        responseType: ResponseType.json,
      ),
    );

    final data = (res.data is Map<String, dynamic>)
        ? (res.data as Map<String, dynamic>)
        : <String, dynamic>{'data': res.data};

    String readString(String key) {
      final v = data[key];
      if (v is String) return v.trim();
      return '';
    }

    // Try a few common response shapes without being strict.
    final name = readString('name').isNotEmpty ? readString('name') : readString('medication_name');
    final dosage = readString('dosage').isNotEmpty ? readString('dosage') : readString('dose');
    final instructions = readString('instructions').isNotEmpty
        ? readString('instructions')
        : readString('direction');

    return ScanMedicationAiResult(
      name: name,
      dosage: dosage,
      instructions: instructions,
      raw: data,
    );
  }
}

