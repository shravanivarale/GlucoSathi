/// Network layer contract for communicating with the GlucoSaathi backend.
///
/// The concrete HTTP implementation (e.g. `Dio` or `http`) is intentionally
/// out of scope for the MVP architecture phase.
library;

import 'dart:io';

/// Sends multipart requests to backend endpoints.
abstract class ApiClient {
  /// Uploads [image] to `POST /api/v1/food/analyze` and returns the decoded
  /// JSON response payload as a `Map`.
  Future<Map<String, dynamic>> analyzeFood(File image);
}