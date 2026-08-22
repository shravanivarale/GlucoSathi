/// Indian Food Composition (INDB / IFCT) database models and portion units.
///
/// Contains standard portion sizes and macronutrient facts for unpackaged
/// Indian dishes, plus preset items for packaged barcode scanning.
library;

/// Represents a household portion unit for an Indian dish.
class IndbPortionUnit {
  const IndbPortionUnit({
    required this.name,
    required this.gramWeight,
    required this.carbGrams,
  });

  /// Human-readable name, e.g. "1 Katori", "1 Medium Roti", "1 Plate".
  final String name;

  /// Approximate weight in grams for this portion.
  final double gramWeight;

  /// Carbohydrate amount in grams for this specific portion unit.
  final double carbGrams;
}

/// Represents an unpackaged/home-cooked Indian food dish.
class IndbFoodDish {
  const IndbFoodDish({
    required this.id,
    required this.name,
    required this.category,
    required this.portionUnits,
    required this.defaultPortionIndex,
    required this.carbsPer100g,
    this.proteinPer100g = 0,
    this.fatPer100g = 0,
    this.fiberPer100g = 0,
    this.caloriesPer100g = 0,
    this.isHighFatProtein = false,
  });

  final String id;
  final String name;
  final String category;
  final List<IndbPortionUnit> portionUnits;
  final int defaultPortionIndex;
  final double carbsPer100g;
  final double proteinPer100g;
  final double fatPer100g;
  final double fiberPer100g;
  final double caloriesPer100g;
  final bool isHighFatProtein;

  IndbPortionUnit get defaultPortion => portionUnits[defaultPortionIndex];
}

/// Preset item for packaged/store-bought barcode scanning simulation.
class PackagedFoodPreset {
  const PackagedFoodPreset({
    required this.barcode,
    required this.name,
    required this.brand,
    required this.servingSizeText,
    required this.totalCarbsPerServing,
    required this.fiberPerServing,
  });

  final String barcode;
  final String name;
  final String brand;
  final String servingSizeText;
  final double totalCarbsPerServing;
  final double fiberPerServing;

  double get netCarbsPerServing =>
      (totalCarbsPerServing - fiberPerServing).clamp(0.0, double.infinity);
}

/// Pre-populated database of popular Indian dishes (INDB/IFCT) and packaged items.
class IndbFoodDatabase {
  const IndbFoodDatabase._();

  /// Standard list of popular Indian dishes with authentic portion units.
  static const List<IndbFoodDish> dishes = [
    IndbFoodDish(
      id: 'roti_chapati',
      name: 'Roti / Chapati (Whole Wheat)',
      category: 'Breads',
      carbsPer100g: 46.0,
      proteinPer100g: 11.5,
      fatPer100g: 3.5,
      fiberPer100g: 10.0,
      caloriesPer100g: 275.0,
      defaultPortionIndex: 1,
      portionUnits: [
        IndbPortionUnit(name: '1 Small Roti (25g)', gramWeight: 25, carbGrams: 11.5),
        IndbPortionUnit(name: '1 Medium Roti (40g)', gramWeight: 40, carbGrams: 18.4),
        IndbPortionUnit(name: '1 Large Roti (60g)', gramWeight: 60, carbGrams: 27.6),
      ],
    ),
    IndbFoodDish(
      id: 'dal_tadka',
      name: 'Dal Tadka (Toor/Yellow Dal)',
      category: 'Lentils & Curries',
      carbsPer100g: 10.5,
      proteinPer100g: 4.8,
      fatPer100g: 3.2,
      fiberPer100g: 2.8,
      caloriesPer100g: 92.0,
      defaultPortionIndex: 0,
      portionUnits: [
        IndbPortionUnit(name: '1 Katori (150g)', gramWeight: 150, carbGrams: 15.8),
        IndbPortionUnit(name: '1 Small Bowl (100g)', gramWeight: 100, carbGrams: 10.5),
        IndbPortionUnit(name: '1 Large Bowl (250g)', gramWeight: 250, carbGrams: 26.3),
      ],
    ),
    IndbFoodDish(
      id: 'rajma_curry',
      name: 'Rajma Masala / Curry',
      category: 'Lentils & Curries',
      carbsPer100g: 14.5,
      proteinPer100g: 6.2,
      fatPer100g: 4.5,
      fiberPer100g: 5.1,
      caloriesPer100g: 125.0,
      defaultPortionIndex: 0,
      portionUnits: [
        IndbPortionUnit(name: '1 Katori (150g)', gramWeight: 150, carbGrams: 21.8),
        IndbPortionUnit(name: '1 Plate Serving (250g)', gramWeight: 250, carbGrams: 36.3),
      ],
    ),
    IndbFoodDish(
      id: 'cooked_white_rice',
      name: 'Cooked White Rice (Basmati/Sona Masoori)',
      category: 'Rice & Grains',
      carbsPer100g: 28.0,
      proteinPer100g: 2.7,
      fatPer100g: 0.3,
      fiberPer100g: 0.4,
      caloriesPer100g: 130.0,
      defaultPortionIndex: 0,
      portionUnits: [
        IndbPortionUnit(name: '1 Katori (100g)', gramWeight: 100, carbGrams: 28.0),
        IndbPortionUnit(name: '1 Medium Bowl (150g)', gramWeight: 150, carbGrams: 42.0),
        IndbPortionUnit(name: '1 Plate (250g)', gramWeight: 250, carbGrams: 70.0),
      ],
    ),
    IndbFoodDish(
      id: 'rajma_chawal',
      name: 'Rajma Chawal Combo',
      category: 'Combos & Meals',
      carbsPer100g: 22.0,
      proteinPer100g: 4.8,
      fatPer100g: 3.5,
      fiberPer100g: 3.2,
      caloriesPer100g: 140.0,
      defaultPortionIndex: 0,
      portionUnits: [
        IndbPortionUnit(name: '1 Standard Plate (350g)', gramWeight: 350, carbGrams: 77.0),
        IndbPortionUnit(name: '1 Half Plate (200g)', gramWeight: 200, carbGrams: 44.0),
      ],
    ),
    IndbFoodDish(
      id: 'paneer_butter_masala',
      name: 'Paneer Butter Masala',
      category: 'Paneer & Dairy',
      carbsPer100g: 7.2,
      proteinPer100g: 9.0,
      fatPer100g: 16.5,
      fiberPer100g: 1.8,
      caloriesPer100g: 215.0,
      isHighFatProtein: true,
      defaultPortionIndex: 0,
      portionUnits: [
        IndbPortionUnit(name: '1 Katori (150g)', gramWeight: 150, carbGrams: 10.8),
        IndbPortionUnit(name: '1 Serving Bowl (200g)', gramWeight: 200, carbGrams: 14.4),
      ],
    ),
    IndbFoodDish(
      id: 'poha',
      name: 'Poha (Flattened Rice with Peanuts & Veggies)',
      category: 'Breakfast',
      carbsPer100g: 26.5,
      proteinPer100g: 3.8,
      fatPer100g: 6.5,
      fiberPer100g: 2.5,
      caloriesPer100g: 180.0,
      defaultPortionIndex: 0,
      portionUnits: [
        IndbPortionUnit(name: '1 Plate (150g)', gramWeight: 150, carbGrams: 39.8),
        IndbPortionUnit(name: '1 Katori (100g)', gramWeight: 100, carbGrams: 26.5),
      ],
    ),
    IndbFoodDish(
      id: 'idli_sambar',
      name: 'Idli with Sambar (Steamed Rice Cakes)',
      category: 'Breakfast',
      carbsPer100g: 18.0,
      proteinPer100g: 3.5,
      fatPer100g: 0.8,
      fiberPer100g: 1.6,
      caloriesPer100g: 95.0,
      defaultPortionIndex: 0,
      portionUnits: [
        IndbPortionUnit(name: '2 Pieces (100g)', gramWeight: 100, carbGrams: 24.0),
        IndbPortionUnit(name: '1 Piece (50g)', gramWeight: 50, carbGrams: 12.0),
        IndbPortionUnit(name: '3 Pieces (150g)', gramWeight: 150, carbGrams: 36.0),
      ],
    ),
    IndbFoodDish(
      id: 'masala_dosa',
      name: 'Masala Dosa with Potato Filling',
      category: 'Breakfast',
      carbsPer100g: 27.0,
      proteinPer100g: 4.5,
      fatPer100g: 9.0,
      fiberPer100g: 2.2,
      caloriesPer100g: 210.0,
      defaultPortionIndex: 0,
      portionUnits: [
        IndbPortionUnit(name: '1 Medium Dosa (150g)', gramWeight: 150, carbGrams: 40.5),
        IndbPortionUnit(name: '1 Large Dosa (220g)', gramWeight: 220, carbGrams: 59.4),
      ],
    ),
    IndbFoodDish(
      id: 'chicken_biryani',
      name: 'Chicken Biryani (Dum Style)',
      category: 'Rice & Grains',
      carbsPer100g: 21.0,
      proteinPer100g: 8.5,
      fatPer100g: 7.2,
      fiberPer100g: 1.4,
      caloriesPer100g: 185.0,
      isHighFatProtein: true,
      defaultPortionIndex: 0,
      portionUnits: [
        IndbPortionUnit(name: '1 Standard Plate (300g)', gramWeight: 300, carbGrams: 63.0),
        IndbPortionUnit(name: '1 Half Plate (180g)', gramWeight: 180, carbGrams: 37.8),
      ],
    ),
    IndbFoodDish(
      id: 'aloo_paratha',
      name: 'Aloo Paratha with Butter/Ghee',
      category: 'Breads',
      carbsPer100g: 32.0,
      proteinPer100g: 5.5,
      fatPer100g: 11.0,
      fiberPer100g: 3.5,
      caloriesPer100g: 250.0,
      isHighFatProtein: true,
      defaultPortionIndex: 0,
      portionUnits: [
        IndbPortionUnit(name: '1 Paratha (100g)', gramWeight: 100, carbGrams: 32.0),
        IndbPortionUnit(name: '2 Parathas (200g)', gramWeight: 200, carbGrams: 64.0),
      ],
    ),
    IndbFoodDish(
      id: 'masala_chai',
      name: 'Indian Masala Chai (with Milk & 1 tsp Sugar)',
      category: 'Beverages',
      carbsPer100g: 7.0,
      proteinPer100g: 1.8,
      fatPer100g: 2.0,
      fiberPer100g: 0.0,
      caloriesPer100g: 55.0,
      defaultPortionIndex: 0,
      portionUnits: [
        IndbPortionUnit(name: '1 Standard Cup (150ml)', gramWeight: 150, carbGrams: 10.5),
        IndbPortionUnit(name: '1 Small Cutting Cup (90ml)', gramWeight: 90, carbGrams: 6.3),
        IndbPortionUnit(name: '1 Mug (250ml)', gramWeight: 250, carbGrams: 17.5),
      ],
    ),
  ];

  /// Preset packaged goods for barcode scanner simulation and lookups.
  static const List<PackagedFoodPreset> packagedPresets = [
    PackagedFoodPreset(
      barcode: '8901030368142',
      name: 'NutriChoice Digestive Biscuits',
      brand: 'Britannia',
      servingSizeText: '2 Biscuits (25g)',
      totalCarbsPerServing: 17.5,
      fiberPerServing: 2.8,
    ),
    PackagedFoodPreset(
      barcode: '8901262010017',
      name: 'Amul Taaza Homogenised Milk',
      brand: 'Amul',
      servingSizeText: '1 Glass (200ml)',
      totalCarbsPerServing: 9.6,
      fiberPerServing: 0.0,
    ),
    PackagedFoodPreset(
      barcode: '8901058852333',
      name: 'Maggi 2-Minute Masala Noodles',
      brand: 'Nestlé',
      servingSizeText: '1 Single Pack (70g)',
      totalCarbsPerServing: 42.0,
      fiberPerServing: 2.5,
    ),
    PackagedFoodPreset(
      barcode: '8906076241029',
      name: 'Greek Yogurt Natural (Unsweetened)',
      brand: 'Epigamia',
      servingSizeText: '1 Cup (90g)',
      totalCarbsPerServing: 4.5,
      fiberPerServing: 0.0,
    ),
    PackagedFoodPreset(
      barcode: '8901725131018',
      name: 'Dark Fantasy Choco Fills',
      brand: 'Sunfeast',
      servingSizeText: '1 Cookie (15g)',
      totalCarbsPerServing: 10.2,
      fiberPerServing: 0.4,
    ),
  ];

  /// Quick frequent log items for 1-tap logging.
  static const List<Map<String, dynamic>> quickLogItems = [
    {'label': '2 Roti', 'carbs': 36.8, 'unit': '2 Medium Roti (80g)', 'dishId': 'roti_chapati'},
    {'label': '1 Katori Dal', 'carbs': 15.8, 'unit': '1 Katori (150g)', 'dishId': 'dal_tadka'},
    {'label': '1 Katori Rice', 'carbs': 28.0, 'unit': '1 Katori (100g)', 'dishId': 'cooked_white_rice'},
    {'label': '1 Cup Chai', 'carbs': 10.5, 'unit': '1 Cup (150ml)', 'dishId': 'masala_chai'},
    {'label': '1 Plate Poha', 'carbs': 39.8, 'unit': '1 Plate (150g)', 'dishId': 'poha'},
    {'label': '1 Aloo Paratha', 'carbs': 32.0, 'unit': '1 Paratha (100g)', 'dishId': 'aloo_paratha'},
    {'label': '2 Idli + Sambar', 'carbs': 24.0, 'unit': '2 Pieces (100g)', 'dishId': 'idli_sambar'},
  ];
}
