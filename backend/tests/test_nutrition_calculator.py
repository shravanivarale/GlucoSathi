"""Tests for the serving-size calculation (synthetic data only)."""

from pydantic import ValidationError

from app.models.food import FoodNutrition
from app.services.nutrition_calculator import nutrition_for_serving
from tests.synthetic_data import SYNTHETIC_NUTRITION

PER_100G = SYNTHETIC_NUTRITION[0]


def test_nutrition_for_serving_scales_all_fields():
    # 20 g carbs per 100 g × 250 g serving = 50 g.
    serving = nutrition_for_serving(PER_100G, serving_size_g=250)

    assert serving.food_id == "TEST_001"
    assert serving.serving_size_g == 250
    assert serving.nutrition_source == "TEST_DATASET"
    assert serving.carbs_g == 50.0
    assert serving.protein_g == 25.0
    assert serving.fat_g == 12.5
    assert serving.fiber_g == 10.0
    assert serving.calories == 250.0


def test_nutrition_for_serving_at_100g_is_identity():
    serving = nutrition_for_serving(PER_100G, serving_size_g=100)

    assert serving.carbs_g == 20.0
    assert serving.protein_g == 10.0
    assert serving.fat_g == 5.0
    assert serving.fiber_g == 4.0
    assert serving.calories == 100.0


def test_negative_serving_size_is_rejected():
    try:
        nutrition_for_serving(PER_100G, serving_size_g=-50)
    except ValidationError:
        return
    raise AssertionError("negative serving size must raise ValidationError")


def test_negative_nutrition_values_are_rejected():
    try:
        FoodNutrition(
            food_id="TEST_999",
            nutrition_source="TEST_DATASET",
            carbs_g_per_100g=-1.0,
            protein_g_per_100g=0,
            fat_g_per_100g=0,
            fiber_g_per_100g=0,
            calories_per_100g=0,
        )
    except ValidationError:
        return
    raise AssertionError("negative per-100g value must raise ValidationError")