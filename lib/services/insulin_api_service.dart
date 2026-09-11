/// Insulin log API service for communicating with the GlucoSaathi backend.
///
/// Provides CRUD for insulin dose logs.  The logged data is consumed by the
/// CGM prediction pipeline on the backend to compute IOB features.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../core/constants/api_constants.dart';
import '../core/errors/app_failure.dart';

/// A single insulin log entry.
class InsulinLog {
  final int id;
  final double doseUnits;
  final String insulinType;
  final String displayName;
  final String loggedAt;

  InsulinLog({
    required this.id,
    required this.doseUnits,
    required this.insulinType,
    required this.displayName,
    required this.loggedAt,
  });

  factory InsulinLog.fromJson(Map<String, dynamic> json) {
    return InsulinLog(
      id: json['id'] as int,
      doseUnits: (json['dose_units'] as num).toDouble(),
      insulinType: json['insulin_type'] as String,
      displayName: json['display_name'] as String? ?? json['insulin_type'] as String,
      loggedAt: json['logged_at'] as String,
    );
  }
}

/// Current Insulin on Board, broken down by type.
class IOBResult {
  final double totalIob;
  final double iobRapid;
  final double iobRegular;
  final double iobNph;

  IOBResult({
    required this.totalIob,
    required this.iobRapid,
    required this.iobRegular,
    required this.iobNph,
  });

  factory IOBResult.fromJson(Map<String, dynamic> json) {
    return IOBResult(
      totalIob: (json['total_iob'] as num).toDouble(),
      iobRapid: (json['iob_rapid'] as num).toDouble(),
      iobRegular: (json['iob_regular'] as num).toDouble(),
      iobNph: (json['iob_nph'] as num).toDouble(),
    );
  }
}

/// Service for insulin log API calls.
class InsulinApiService {
  InsulinApiService({http.Client? httpClient})
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

  /// Fetch recent insulin logs (newest first).
  Future<List<InsulinLog>> getInsulinLogs({int limit = 100}) async {
    final response = await _get(
      '${ApiEndpoints.insulinLogs}?limit=$limit',
    );
    final logs = response['logs'] as List<dynamic>? ?? [];
    return logs
        .map((l) => InsulinLog.fromJson(l as Map<String, dynamic>))
        .toList();
  }

  /// Log a new insulin dose.
  Future<InsulinLog> logInsulin({
    required double doseUnits,
    required String insulinType,
    required String loggedAt,
    String? displayName,
  }) async {
    final response = await _post(ApiEndpoints.insulinLog, {
      'dose_units': doseUnits,
      'insulin_type': insulinType,
      'display_name': displayName ?? insulinType,
      'logged_at': loggedAt,
    });
    return InsulinLog.fromJson(response);
  }

  /// Delete an insulin log entry.
  Future<void> deleteInsulinLog(int id) async {
    await _delete(ApiEndpoints.insulinLogDelete(id));
  }

  /// Fetch current Insulin on Board from the backend.
  ///
  /// This is the single source of truth for IOB, used by both the Home and
  /// CGM screens.  The backend computes IOB from all stored insulin logs
  /// using type-specific pharmacokinetic decay functions.
  Future<IOBResult> getIOB() async {
    final response = await _get(ApiEndpoints.insulinIOB);
    return IOBResult.fromJson(response);
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
      throw const NetworkFailure('The insulin service took too long to respond.');
    } on SocketException {
      throw const NetworkFailure(
        'Could not connect to the insulin service. Please try again.',
      );
    } on http.ClientException {
      throw const NetworkFailure(
        'Could not connect to the insulin service. Please try again.',
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
      throw const NetworkFailure('The insulin service took too long to respond.');
    } on SocketException {
      throw const NetworkFailure(
        'Could not connect to the insulin service. Please try again.',
      );
    } on http.ClientException {
      throw const NetworkFailure(
        'Could not connect to the insulin service. Please try again.',
      );
    } on AppFailure {
      rethrow;
    }
  }

  Future<void> _delete(String path) async {
    try {
      final response = await _httpClient
          .delete(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw UnknownFailure(
          'Failed to delete insulin log: ${response.statusCode}',
        );
      }
    } on TimeoutException {
      throw const NetworkFailure('The insulin service took too long to respond.');
    } on SocketException {
      throw const NetworkFailure(
        'Could not connect to the insulin service. Please try again.',
      );
    } on http.ClientException {
      throw const NetworkFailure(
        'Could not connect to the insulin service. Please try again.',
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
    throw const UnknownFailure('The insulin service returned an unexpected response.');
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
      'The insulin service returned status code $statusCode.';
}
