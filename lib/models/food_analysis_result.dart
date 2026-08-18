/// Models for the response of `POST /api/v1/foods/analyze`.
///
/// Mirrors `FoodAnalyzeResponse` / the `nutrition` object in
/// `docs/api-contract.md`. All values come from the backend (INDB for
/// nutrition) — the Flutter client never derives them locally.
library;

/// Result of analyzing a food image.
class FoodAnalysis {
  const FoodAnalysis({
    required this.recognizedFood,
    required this.matched,
    this.nutrition,
    this.message,
  });

  /// Canonical food name produced by the backend recognition service.
  final String recognizedFood;

  /// Whether the recognized food had a matching nutrition entry.
  final bool matched;

  /// INDB nutrition values, present only when [matched] is `true`.
  final FoodNutrition? nutrition;

  /// Backend-provided note, e.g. when no reliable match exists.
  final String? message;

  /// Builds a [FoodAnalysis] from the backend response map.
  factory FoodAnalysis.fromJson(Map<String, dynamic> json) {
    final nutritionJson = json['nutrition'];
    return FoodAnalysis(
      recognizedFood: json['recognized_food'] as String? ?? '',
      matched: json['matched'] as bool? ?? false,
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