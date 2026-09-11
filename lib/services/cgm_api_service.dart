/// CGM API service for communicating with the GlucoSaathi backend.
///
/// Follows the same raw `package:http` pattern as [GlucoseApiService].
/// All CGM provider communication goes through the backend — Flutter
/// never talks directly to Dexcom or any other provider.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/constants/api_constants.dart';
import '../core/errors/app_failure.dart';
import '../models/cgm_connection.dart';

/// Service for CGM backend API calls.
///
/// Architecture:
/// ```
/// Flutter → CgmApiService → GlucoSaathi Backend → CGM Provider
/// ```
class CgmApiService {
  CgmApiService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  final http.Client _httpClient;

  static const String _baseUrlOverride =
      String.fromEnvironment('API_BASE_URL');

  static String get _baseUrl {
    if (_baseUrlOverride.isNotEmpty) {
      return _baseUrlOverride;
    }
    return 'http://10.0.2.2:8082';
  }

  /// Fetch the current CGM provider connection status from the backend.
  Future<CgmBackendStatus> getCGMStatus() async {
    final response = await _get(ApiEndpoints.cgmStatus);
    return CgmBackendStatus.fromJson(response);
  }

  /// Fetch the single most recent CGM glucose reading.
  Future<CgmBackendReading> getLatestCGMReading() async {
    final response = await _get(ApiEndpoints.cgmReadingLatest);
    return CgmBackendReading.fromJson(response);
  }

  /// Fetch CGM glucose history.
  ///
  /// [limit] controls the number of readings (default 288 = 24h at 5-min).
  Future<List<CgmBackendReading>> getCGMHistory({int limit = 288}) async {
    final response = await _get(
      '${ApiEndpoints.cgmReadings}?limit=$limit',
    );
    final readings = response['readings'] as List<dynamic>? ?? [];
    return readings
        .map((r) => CgmBackendReading.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Run glucose prediction using CGM history via the existing ML pipeline.
  ///
  /// The backend fetches CGM readings, preprocesses them with the existing
  /// `preprocess_history()`, and runs the ONNX model.
  Future<CgmPrediction> predictFromCGM() async {
    final response = await _post(ApiEndpoints.cgmPredict, {});
    print('[CGM-API] Raw predict response: $response');
    final prediction = CgmPrediction.fromJson(response);
    print('[CGM-API] Parsed: 30min=${prediction.prediction30Min}, '
        '60min=${prediction.prediction60Min}, iob=${prediction.totalIob}');
    return prediction;
  }

  /// Connect the current CGM provider and persist the state.
  Future<CgmBackendStatus> connectCGM() async {
    final response = await _post(ApiEndpoints.cgmConnect, {});
    return CgmBackendStatus.fromJson(response);
  }

  /// Disconnect the current CGM provider and remove persisted state.
  Future<CgmBackendStatus> disconnectCGM() async {
    final response = await _post(ApiEndpoints.cgmDisconnect, {});
    return CgmBackendStatus.fromJson(response);
  }

  // ── HTTP helpers ────────────────────────────────────────────────────

  Future<Map<String, dynamic>> _get(String path) async {
    try {
      final response = await _httpClient
          .get(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 30));

      return _decode(response);
    } on TimeoutException {
      throw const NetworkFailure('The CGM service took too long to respond.');
    } on SocketException {
      throw const NetworkFailure(
        'Could not connect to the CGM service. Please try again.',
      );
    } on http.ClientException {
      throw const NetworkFailure(
        'Could not connect to the CGM service. Please try again.',
      );
    } on AppFailure {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _httpClient
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));

      return _decode(response);
    } on TimeoutException {
      throw const NetworkFailure('The CGM service took too long to respond.');
    } on SocketException {
      throw const NetworkFailure(
        'Could not connect to the CGM service. Please try again.',
      );
    } on http.ClientException {
      throw const NetworkFailure(
        'Could not connect to the CGM service. Please try again.',
      );
    } on AppFailure {
      rethrow;
    }
  }

  Map<String, dynamic> _decode(http.Response response) {
    final body = _decodeBody(response);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }
    throw _failureFor(response.statusCode, body);
  }

  Map<String, dynamic> _decodeBody(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      // Fall through to the generic failure below.
    }
    throw const UnknownFailure('The CGM service returned an unexpected response.');
  }

  AppFailure _failureFor(int statusCode, Map<String, dynamic> body) {
    final error = body['error'];
    if (error is Map<String, dynamic>) {
      final message =
          error['message'] as String? ?? _messageFor(statusCode);
      return UnknownFailure(message);
    }
    return UnknownFailure(_messageFor(statusCode));
  }

  String _messageFor(int statusCode) =>
      'The CGM service returned status code $statusCode.';
}
