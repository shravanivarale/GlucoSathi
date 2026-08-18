/// Central place for API-related constants used by the Food Recognition MVP.
library;

/// Endpoint paths for the GlucoSaathi backend API.
///
/// Contract details are documented in `docs/api-contract.md`.
abstract final class ApiEndpoints {
  ApiEndpoints._();

  /// Relative path for food image analysis (recognized food + INDB nutrition).
  static const String foodsAnalyze = '/api/v1/foods/analyze';

  /// Relative path that only names the food in an uploaded image.
  static const String foodsRecognize = '/api/v1/foods/recognize';
}