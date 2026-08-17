/// Central place for API-related constants used by the Food Recognition MVP.
library;

/// Endpoint paths for the GlucoSaathi backend API.
///
/// Contract details are documented in `docs/api-contract.md`.
abstract final class ApiEndpoints {
  ApiEndpoints._();

  /// Relative path for food image analysis.
  static const String foodAnalyze = '/api/v1/food/analyze';
}