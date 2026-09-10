/// Models for the response of `POST /api/v1/foods/analyze`.
///
/// Mirrors `FoodAnalyzeResponse` / the unified multi-food response format.
/// All values come from the backend (INDB for nutrition) — the Flutter client
/// never derives them locally.
///
/// A single consistent format is used for both single-food and multi-food
/// images: `foods` always contains a list (one element for a single-food
/// image, multiple elements for a meal).  `totalNutrition` sums per-100g
/// values across all matched items.
library;

/// Result of analyzing a food image — contains one or more food items.
class FoodAnalysis {
  const FoodAnalysis({
    required this.foods,
    this.totalNutrition,
  });

  /// Per-food analysis results. Always at least one element.
  final List<SingleFoodResult> foods;

  /// Aggregated nutrition totals across all matched foods, or null when
  /// nothing was matched.
  final Map<String, double>? totalNutrition;

  /// Builds a [FoodAnalysis] from the backend response map.
  factory FoodAnalysis.fromJson(Map<String, dynamic> json) {
    final foodsList = json['foods'] as List<dynamic>? ?? [];
    final foods = foodsList
        .map((e) => SingleFoodResult.fromJson(e as Map<String, dynamic>))
        .toList();

    final totalJson = json['total_nutrition'];
    final totalNutrition = totalJson is Map<String, dynamic>
        ? totalJson.map((k, v) => MapEntry(k, (v as num?)?.toDouble() ?? 0))
        : null;

    return FoodAnalysis(
      foods: foods,
      totalNutrition: totalNutrition,
    );
  }
}

/// Per-food analysis result within a meal response.
class SingleFoodResult {
  const SingleFoodResult({
    required this.recognizedFood,
    required this.matched,
    this.foodId,
    this.foodName,
    this.nutrition,
    this.message,
  });

  /// Canonical food name produced by the backend recognition service.
  final String recognizedFood;

  /// Whether the recognized food had a matching nutrition entry.
  final bool matched;

  /// INDB food identifier, present only when [matched] is `true`.
  final String? foodId;

  /// Canonical INDB food name, present only when [matched] is `true`.
  final String? foodName;

  /// INDB nutrition values, present only when [matched] is `true`.
  final FoodNutrition? nutrition;

  /// Backend-provided note, e.g. when no reliable match exists.
  final String? message;

  /// Builds a [SingleFoodResult] from the backend's per-food object.
  factory SingleFoodResult.fromJson(Map<String, dynamic> json) {
    final nutritionJson = json['nutrition'];
    return SingleFoodResult(
      recognizedFood: json['recognized_food'] as String? ?? '',
      matched: json['matched'] as bool? ?? false,
      foodId: json['food_id'] as String?,
      foodName: json['food_name'] as String?,
      nutrition: nutritionJson is Map<String, dynamic>
          ? FoodNutrition.fromJson(nutritionJson)
          : null,
      message: json['message'] as String?,
    );
  }
}

/// Nutrition values returned by the backend on a per-100g basis.
class FoodNutrition {
  const FoodNutrition({
    required this.carbG,
    required this.proteinG,
    required this.fatG,
    required this.fibreG,
    required this.energyKcal,
    required this.basis,
    required this.nutritionSource,
  });

  /// Carbohydrates in grams per 100 g.
  final double carbG;

  /// Protein in grams per 100 g.
  final double proteinG;

  /// Fat in grams per 100 g.
  final double fatG;

  /// Dietary fibre in grams per 100 g.
  final double fibreG;

  /// Energy in kilocalories per 100 g.
  final double energyKcal;

  /// Basis the values are reported on, e.g. "per_100g".
  final String basis;

  /// Nutrition database the values were sourced from, e.g. "INDB".
  final String nutritionSource;

  /// Builds a [FoodNutrition] from the backend's `nutrition` object.
  factory FoodNutrition.fromJson(Map<String, dynamic> json) {
    return FoodNutrition(
      carbG: (json['carb_g'] as num?)?.toDouble() ?? 0,
      proteinG: (json['protein_g'] as num?)?.toDouble() ?? 0,
      fatG: (json['fat_g'] as num?)?.toDouble() ?? 0,
      fibreG: (json['fibre_g'] as num?)?.toDouble() ?? 0,
      energyKcal: (json['energy_kcal'] as num?)?.toDouble() ?? 0,
      basis: json['basis'] as String? ?? '',
      nutritionSource: json['nutrition_source'] as String? ?? '',
    );
  }
}
