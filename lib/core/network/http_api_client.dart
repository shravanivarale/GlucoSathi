/// Concrete HTTP implementation of [ApiClient] backed by `package:http`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../constants/api_constants.dart';
import '../errors/app_failure.dart';
import '../utils/image_format.dart';
import 'api_client.dart';

/// Sends multipart requests to the GlucoSaathi backend over HTTP.
class HttpApiClient implements ApiClient {
  HttpApiClient({
    http.Client? httpClient,
    Uri? baseUri,
    Duration? timeout,
  })  : _httpClient = httpClient ?? http.Client(),
        _baseUri = baseUri ?? defaultBaseUri,
        _timeout = timeout ?? defaultTimeout;

  /// Timeout applied to each HTTP request when none is configured.
  ///
  /// Must comfortably cover the backend's bounded Gemini Vision call (60 s per
  /// attempt plus retries). A tighter timeout would abandon in-flight
  /// recognition and report "The backend took too long to respond."
  static const Duration defaultTimeout = Duration(seconds: 90);

  /// Optional compile-time base URL override, e.g.
  /// `flutter run --dart-define=API_BASE_URL=http://192.168.1.5:8000`.
  static const String _baseUrlOverride = String.fromEnvironment('API_BASE_URL');

  /// Default backend base URL for local development.
  ///
  /// Points at the Android emulator's host loopback alias (`10.0.2.2`) so the
  /// app reaches a backend running on the development machine. Set
  /// `API_BASE_URL` via `--dart-define` to use another target while
  /// developing. No production URL is baked in.
  static Uri get defaultBaseUri {
    final override = _baseUrlOverride;
    if (override.isNotEmpty) {
      return Uri.parse(override);
    }
    return Uri.parse('http://10.0.2.2:8000');
  }

  final http.Client _httpClient;
  final Uri _baseUri;
  final Duration _timeout;

  @override
  Future<Map<String, dynamic>> analyzeFood(File image) async {
    final request = http.MultipartRequest(
      'POST',
      _baseUri.resolve(ApiEndpoints.foodsAnalyze),
    );

    // The backend rejects declared content types other than image/jpeg and
    // image/png. `MultipartFile.fromPath` defaults to application/octet-stream,
    // so derive the correct MIME from the actual bytes (never from the
    // filename extension or picker MIME metadata, which are unreliable).
    final mimeType = imageMimeType(image);
    request.files.add(
      await http.MultipartFile.fromPath(
        'image',
        image.path,
        contentType:
            mimeType == null ? null : http.MediaType.parse(mimeType),
      ),
    );

    try {
      final streamed = await _httpClient.send(request).timeout(_timeout);
      final response =
          await http.Response.fromStream(streamed).timeout(_timeout);
      return _decode(response);
    } on TimeoutException {
      throw const NetworkFailure('The backend took too long to respond.');
    } on SocketException {
      throw const NetworkFailure('Could not reach the backend.');
    } on http.ClientException {
      throw const NetworkFailure('Could not reach the backend.');
    } on AppFailure {
      rethrow;
    }
  }

  /// Decodes a successful response body into a JSON map, or maps a non-2xx
  /// response to an [AppFailure] using the backend error envelope.
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
    throw const UnknownFailure('The backend returned an unexpected response.');
  }

  AppFailure _failureFor(int statusCode, Map<String, dynamic> body) {
    final error = body['error'];
    if (error is Map<String, dynamic>) {
      final code = error['code'] as String? ?? '';
      final message =
          error['message'] as String? ?? _messageFor(statusCode);
      return switch (code) {
        'INVALID_IMAGE' => ImageInvalidFailure(message),
        'IMAGE_TOO_LARGE' => ImageTooLargeFailure(message),
        'FOOD_NOT_RECOGNIZED' => FoodNotRecognizedFailure(message),
        'LOW_CONFIDENCE' => LowConfidenceFailure(message),
        'FOOD_NOT_FOUND' => FoodNotFoundFailure(message),
        'NUTRITION_DATA_NOT_FOUND' => NutritionDataNotFoundFailure(message),
        'ANALYSIS_FAILED' => AnalysisFailedFailure(message),
        'INTERNAL_ERROR' => InternalErrorFailure(message),
        _ => UnknownFailure(message),
      };
    }
    return UnknownFailure(_messageFor(statusCode));
  }

  String _messageFor(int statusCode) =>
      'The backend returned status code $statusCode.';
}