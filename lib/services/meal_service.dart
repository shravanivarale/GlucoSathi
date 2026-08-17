/// Contract for the Food Recognition service, consumed by the
/// food recognition screen. No implementation yet.
library;

import 'dart:io';

import '../core/errors/app_failure.dart';
import '../core/network/api_client.dart';
import '../core/utils/result.dart';
import '../models/meal_result.dart';

/// Service that turns a food image into a [MealResult] via the backend.
abstract class MealService {
  /// Analyzes [image] and returns a [Result] wrapping the recognized
  /// [MealResult], or an [AppFailure] when analysis fails.
  Future<Result<MealResult>> analyzeFood(File image);

  /// HTTP client used to reach the backend (contract placeholder).
  ApiClient get client;
}