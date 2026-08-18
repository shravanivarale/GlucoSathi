/// Domain models for a food recognition result.
///
/// Mirrors the `data` object returned by `POST /api/v1/foods/analyze` (see
/// `docs/api-contract.md`). All numeric values are in grams except
/// [NutritionInfo.calories], which is in kilocalories.
class MealResult {
  const MealResult({
    required this.mealId,
    required this.foodId,
    required this.foodName,
    required this.recognitionConfidence,
    required this.estimatedServingSizeG,
    required this.nutrition,
  });

  /// Stable identifier for this analysis result (UUID from the backend).
  final String mealId;

  /// Identifier of the recognized food in the nutrition database.
  final String foodId;

  /// Human-readable food name, e.g. "Rajma Chawal".
  final String foodName;

  /// Recognition model confidence score in the range 0.0–1.0.
  ///
  /// This is an application/model score, not a medically validated
  /// probability.
  final double recognitionConfidence;

  /// Estimated portion size in grams, derived from the image at the
  /// recognition stage. This is an estimate.
  final double estimatedServingSizeG;

  /// Nutrition values for the estimated serving size, sourced from the
  /// nutrition database (never from the recognition model).
  final NutritionInfo nutrition;

  /// Builds a [MealResult] from the snake_case payload returned by the API.
  factory MealResult.fromJson(Map<String, dynamic> json) {
    return MealResult(
      mealId: json['meal_id'] as String,
      foodId: json['food_id'] as String,
      foodName: json['food_name'] as String,
      recognitionConfidence:
          (json['recognition_confidence'] as num).toDouble(),
      estimatedServingSizeG:
          (json['estimated_serving_size_g'] as num).toDouble(),
      nutrition: NutritionInfo.fromJson(
        json['nutrition'] as Map<String, dynamic>,
      ),
    );
  }

  /// Serializes this [MealResult] to a snake_case JSON map.
  Map<String, dynamic> toJson() {
    return {
      'meal_id': mealId,
      'food_id': foodId,
      'food_name': foodName,
      'recognition_confidence': recognitionConfidence,
      'estimated_serving_size_g': estimatedServingSizeG,
      'nutrition': nutrition.toJson(),
    };
  }
}

/// Nutrition values for the estimated serving size.
///
/// Sourced from the nutrition database (e.g. INDB) — never from the
/// recognition model.
class NutritionInfo {
  const NutritionInfo({
    required this.carbsG,
    required this.proteinG,
    required this.fatG,
    required this.fiberG,
    required this.calories,
    required this.nutritionSource,
  });

  /// Carbohydrates in grams.
  final double carbsG;

  /// Protein in grams.
  final double proteinG;

  /// Fat in grams.
  final double fatG;

  /// Dietary fiber in grams.
  final double fiberG;

  /// Total energy in kilocalories.
  final double calories;

  /// Source nutrition database identifier, e.g. "INDB".
  final String nutritionSource;

  /// Builds a [NutritionInfo] from the snake_case payload returned by the API.
  factory NutritionInfo.fromJson(Map<String, dynamic> json) {
    return NutritionInfo(
      carbsG: (json['carbs_g'] as num).toDouble(),
      proteinG: (json['protein_g'] as num).toDouble(),
      fatG: (json['fat_g'] as num).toDouble(),
      fiberG: (json['fiber_g'] as num).toDouble(),
      calories: (json['calories'] as num).toDouble(),
      nutritionSource: json['nutrition_source'] as String,
    );
  }

  /// Serializes this [NutritionInfo] to a snake_case JSON map.
  Map<String, dynamic> toJson() {
    return {
      'carbs_g': carbsG,
      'protein_g': proteinG,
      'fat_g': fatG,
      'fiber_g': fiberG,
      'calories': calories,
      'nutrition_source': nutritionSource,
    };
  }
}