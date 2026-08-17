"""Synthetic, test-only nutrition data (NEVER production seed data).

Used exclusively by unit tests. The values are invented round numbers chosen
for legible assertions (e.g. 20 g carbs per 100 g × 250 g serving = 50 g).

``nutrition_source`` uses the sentinel value ``TEST_DATASET`` so synthetic
records can never be mistaken for real dataset (INDB/IFCT) entries. This
module must never be used as a source of production records.
"""

from app.models.food import Food, FoodNutrition

SYNTHETIC_FOODS: list[Food] = [
    Food(
        food_id="TEST_001",
        food_name="Synthetic Rice Dish",
        category="Test",
        nutrition_source="TEST_DATASET",
        reference_serving_g=250,
    ),
    Food(
        food_id="TEST_002",
        food_name="Synthetic Lentil Soup",
        category="Test",
        nutrition_source="TEST_DATASET",
        reference_serving_g=200,
    ),
]

SYNTHETIC_NUTRITION: list[FoodNutrition] = [
    FoodNutrition(
        food_id="TEST_001",
        nutrition_source="TEST_DATASET",
        carbs_g_per_100g=20.0,
        protein_g_per_100g=10.0,
        fat_g_per_100g=5.0,
        fiber_g_per_100g=4.0,
        calories_per_100g=100.0,
    ),
    FoodNutrition(
        food_id="TEST_002",
        nutrition_source="TEST_DATASET",
        carbs_g_per_100g=12.0,
        protein_g_per_100g=4.0,
        fat_g_per_100g=2.0,
        fiber_g_per_100g=3.0,
        calories_per_100g=80.0,
    ),
]

SYNTHETIC_ALIASES: dict[str, str] = {
    "synthetic rice dish": "TEST_001",
    "test rice": "TEST_001",
    "synthetic lentil soup": "TEST_002",
}