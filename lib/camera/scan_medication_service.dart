import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../api/endpoints.dart';
import '../config/app_config.dart';

class ScanMedicationAiResult {
  const ScanMedicationAiResult({
    required this.name,
    required this.dosage,
    required this.instructions,
    required this.frequencyPerDay,
    required this.recommendedTimesMinutes,
    required this.raw,
  });

  final String name;
  final String dosage;
  final String instructions;
  final int frequencyPerDay;
  final List<int> recommendedTimesMinutes;
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

    int readInt(String key) {
      final v = data[key];
      if (v is int) return v;
      if (v is num) return v.round();
      if (v is String) return int.tryParse(v.trim()) ?? 0;
      return 0;
    }

    List<int> readIntList(String key) {
      final v = data[key];
      if (v is! List) return const [];
      final out = <int>[];
      for (final item in v) {
        if (item is int) out.add(item);
        if (item is num) out.add(item.round());
        if (item is String) {
          final parsed = int.tryParse(item.trim());
          if (parsed != null) out.add(parsed);
        }
      }
      return out;
    }

    return ScanMedicationAiResult(
      name: name,
      dosage: dosage,
      instructions: instructions,
      frequencyPerDay: readInt('frequency_per_day'),
      recommendedTimesMinutes: readIntList('recommended_times_minutes'),
      raw: data,
    );
  }
}

