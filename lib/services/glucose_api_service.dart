import 'dart:convert';

import 'package:http/http.dart' as http;

class GlucosePrediction {
  final double prediction30Min;
  final double prediction60Min;
  final String unit;

  GlucosePrediction({
    required this.prediction30Min,
    required this.prediction60Min,
    required this.unit,
  });

  factory GlucosePrediction.fromJson(
    Map<String, dynamic> json,
  ) {
    return GlucosePrediction(
      prediction30Min:
          (json['prediction_30_min'] as num).toDouble(),
      prediction60Min:
          (json['prediction_60_min'] as num).toDouble(),
      unit: json['unit'] as String? ?? 'mg/dL',
    );
  }
}


class GlucoseApiService {
  // Local development only.
  // When testing on a physical phone, replace this with
  // your computer's LAN IP address.
  static const String baseUrl =
      'http://10.25.6.217:8000';

  Future<GlucosePrediction> predictRaw(
    List<Map<String, dynamic>> readings,
  ) async {
    if (readings.length < 24) {
      throw Exception(
        'At least 24 glucose readings are required.',
      );
    }

    final response = await http.post(
      Uri.parse(
        '$baseUrl/api/v1/glucose/predict-raw',
      ),
      headers: {
        'Content-Type': 'application/json',
      },
      body: jsonEncode(readings),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Prediction failed: ${response.body}',
      );
    }

    final data =
        jsonDecode(response.body)
            as Map<String, dynamic>;

    return GlucosePrediction.fromJson(data);
  }
}
