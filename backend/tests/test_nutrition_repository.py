"""Tests for the in-memory nutrition repository (synthetic data only)."""

from pydantic import ValidationError

from app.models.errors import (
    FoodNotFoundError,
    NutritionDataNotFoundError,
)
from app.models.food import Food
from app.repositories import InMemoryNutritionRepository
from tests.synthetic_data import (
    SYNTHETIC_ALIASES,
    SYNTHETIC_FOODS,
    SYNTHETIC_NUTRITION,
)


def test_default_repository_starts_empty():
    # The repository must never ship with production/sample food records.
    repo = InMemoryNutritionRepository()

    try:
        repo.get_food("TEST_001")
    except FoodNotFoundError:
        return
    raise AssertionError("empty repository must not return a food")


def test_get_food_returns_canonical_entry():
    repo = InMemoryNutritionRepository(
        foods=SYNTHETIC_FOODS,
        nutrition=SYNTHETIC_NUTRITION,
        aliases=SYNTHETIC_ALIASES,
    )

    food = repo.get_food("TEST_001")

    assert food.food_id == "TEST_001"
    assert food.food_name == "Synthetic Rice Dish"
    assert food.nutrition_source == "TEST_DATASET"


def test_get_food_missing_raises_food_not_found():
    repo = InMemoryNutritionRepository(foods=SYNTHETIC_FOODS)

    try:
        repo.get_food("TEST_999")
    except FoodNotFoundError:
        return
    raise AssertionError("missing food must raise FoodNotFoundError")


def test_get_nutrition_returns_per_100g():
    repo = InMemoryNutritionRepository(
        foods=SYNTHETIC_FOODS,
        nutrition=SYNTHETIC_NUTRITION,
    )

    nutrition = repo.get_nutrition("TEST_001")

    assert nutrition.food_id == "TEST_001"
    assert nutrition.nutrition_source == "TEST_DATASET"
    assert nutrition.carbs_g_per_100g == 20.0
    assert nutrition.calories_per_100g == 100.0


def test_get_nutrition_unknown_food_raises_food_not_found():
    repo = InMemoryNutritionRepository(foods=SYNTHETIC_FOODS)

    try:
        repo.get_nutrition("TEST_999")
    except FoodNotFoundError:
        return
    raise AssertionError("nutrition for unknown food must raise FoodNotFoundError")


def test_get_nutrition_missing_values_raises_nutrition_data_not_found():
    # Food exists, but its nutrition values are unavailable.
    repo = InMemoryNutritionRepository(foods=SYNTHETIC_FOODS)

    try:
        repo.get_nutrition("TEST_001")
    except NutritionDataNotFoundError:
        return
    raise AssertionError(
        "missing nutrition values must raise NutritionDataNotFoundError"
    )


def test_find_food_id_resolves_aliases_to_stable_id():
    repo = InMemoryNutritionRepository(
        foods=SYNTHETIC_FOODS,
        nutrition=SYNTHETIC_NUTRITION,
        aliases=SYNTHETIC_ALIASES,
    )

    assert repo.find_food_id("Synthetic Rice Dish") == "TEST_001"
    assert repo.find_food_id("test rice") == "TEST_001"
    assert repo.find_food_id("Unknown Dish") is None


def test_full_flow_lookup_and_serving_calculation():
    from app.services.nutrition_calculator import nutrition_for_serving

    repo = InMemoryNutritionRepository(
        foods=SYNTHETIC_FOODS,
        nutrition=SYNTHETIC_NUTRITION,
    )

    per_100g = repo.get_nutrition("TEST_001")
    serving = nutrition_for_serving(per_100g, serving_size_g=250)

    assert serving.carbs_g == 50.0
    assert serving.calories == 250.0
    assert serving.nutrition_source == "TEST_DATASET"


def test_food_rejects_non_positive_reference_serving():
    try:
        Food(
            food_id="TEST_999",
            food_name="Synthetic Invalid",
            category="Test",
            nutrition_source="TEST_DATASET",
            reference_serving_g=0,
        )
    except ValidationError:
        return
    raise AssertionError("non-positive reference serving must raise ValidationError")