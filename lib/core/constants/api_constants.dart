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

  /// CGM connection status.
  static const String cgmStatus = '/api/v1/cgm/status';

  /// Latest CGM glucose reading.
  static const String cgmReadingLatest = '/api/v1/cgm/reading/latest';

  /// CGM glucose history.
  static const String cgmReadings = '/api/v1/cgm/readings';

  /// CGM glucose prediction using existing ML pipeline.
  static const String cgmPredict = '/api/v1/cgm/predict';

  /// Connect a CGM provider.
  static const String cgmConnect = '/api/v1/cgm/connect';

  /// Disconnect a CGM provider.
  static const String cgmDisconnect = '/api/v1/cgm/disconnect';

  /// List insulin logs.
  static const String insulinLogs = '/api/v1/insulin/logs';

  /// Log a new insulin dose.
  static const String insulinLog = '/api/v1/insulin/log';

  /// Delete an insulin log entry.
  static String insulinLogDelete(int id) => '/api/v1/insulin/log/$id';

  /// Get current Insulin on Board from backend.
  static const String insulinIOB = '/api/v1/insulin/iob';
}