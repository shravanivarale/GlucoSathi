/// Application-level failure types.
///
/// The `code` of every failure maps 1:1 to an error code documented in
/// `docs/failure-cases.md`. Screens and services switch on these sealed
/// subtypes instead of string-comparing error codes.
library;

/// Base class for all application failures.
sealed class AppFailure implements Exception {
  const AppFailure(this.code, this.message);

  /// Stable, machine-readable code returned by the backend.
  final String code;

  /// Human-readable description of what went wrong.
  final String message;

  @override
  String toString() => 'AppFailure($code): $message';
}

/// No image was provided, or the image is corrupt / in an unsupported format.
class ImageInvalidFailure extends AppFailure {
  const ImageInvalidFailure(String message) : super('INVALID_IMAGE', message);
}

/// The image exceeds the maximum allowed size.
class ImageTooLargeFailure extends AppFailure {
  const ImageTooLargeFailure(String message)
      : super('IMAGE_TOO_LARGE', message);
}

/// The image contains no food, or the food could not be identified.
class FoodNotRecognizedFailure extends AppFailure {
  const FoodNotRecognizedFailure(String message)
      : super('FOOD_NOT_RECOGNIZED', message);
}

/// The food was recognized, but the confidence is below the threshold.
class LowConfidenceFailure extends AppFailure {
  const LowConfidenceFailure(String message) : super('LOW_CONFIDENCE', message);
}

/// The recognized food has no matching entry in the nutrition database.
class FoodNotFoundFailure extends AppFailure {
  const FoodNotFoundFailure(String message) : super('FOOD_NOT_FOUND', message);
}

/// The food exists, but its nutrition values are unavailable.
class NutritionDataNotFoundFailure extends AppFailure {
  const NutritionDataNotFoundFailure(String message)
      : super('NUTRITION_DATA_NOT_FOUND', message);
}

/// The recognition service failed during analysis.
class AnalysisFailedFailure extends AppFailure {
  const AnalysisFailedFailure(String message)
      : super('ANALYSIS_FAILED', message);
}

/// The backend failed with an unexpected internal error.
class InternalErrorFailure extends AppFailure {
  const InternalErrorFailure(String message) : super('INTERNAL_ERROR', message);
}

/// Any unexpected failure that does not map to a known code.
class UnknownFailure extends AppFailure {
  const UnknownFailure(String message) : super('UNKNOWN', message);
}