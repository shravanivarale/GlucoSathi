"""Step 4 — repository food lookup, verified against real INDB data.

End-to-end lookups for the canonical examples ``Poha``, ``Masala dosa``,
``Aloo paratha``: each resolves through Food Normalization (alias -> food_id)
to a canonical food, then returns the correct per-100g nutrition and the
INDB named-serving record, and scales to a serving size.
"""

import pytest

from app.services.nutrition_calculator import nutrition_for_serving

# Per-100g values as stored (rounded to 3 decimals at import).
POHA_PER_100G = dict(carbs=35.048, protein=6.085, fat=14.138, fiber=3.716, kcal=294.526)
POHA_SERVING = dict(name="bowl", carbs=19.133, protein=3.322, fat=7.718, fiber=2.028, kcal=160.781)

DOSA_PER_100G = dict(carbs=19.567, protein=3.288, fat=7.840, fiber=2.523, kcal=164.585)
DOSA_SERVING = dict(name="dosa", carbs=41.024, protein=6.893, fat=16.438, fiber=5.289, kcal=345.076)

PARATHA_PER_100G = dict(carbs=23.92, protein=3.698, fat=10.22, fiber=4.175, kcal=205.042)
PARATHA_SERVING = dict(name="parantha", carbs=22.333, protein=3.452, fat=9.542, fiber=3.898, kcal=191.434)


def _assert_lookup(repo, label, expected_food_id, expected_name, per_100g, serving):
    food_id = repo.find_food_id(label)
    assert food_id == expected_food_id, f"{label!r} must resolve to {expected_food_id}"

    food = repo.get_food(food_id)
    assert food.food_id == expected_food_id
    assert food.food_name == expected_name
    assert food.nutrition_source == "INDB"

    nutrition = repo.get_nutrition(food_id)
    assert nutrition.carbs_g_per_100g == pytest.approx(per_100g["carbs"], rel=1e-3)
    assert nutrition.protein_g_per_100g == pytest.approx(per_100g["protein"], rel=1e-3)
    assert nutrition.fat_g_per_100g == pytest.approx(per_100g["fat"], rel=1e-3)
    assert nutrition.fiber_g_per_100g == pytest.approx(per_100g["fiber"], rel=1e-3)
    assert nutrition.calories_per_100g == pytest.approx(per_100g["kcal"], rel=1e-3)
    assert nutrition.nutrition_source == "INDB"

    serving_record = repo.get_serving(food_id)
    assert serving_record is not None
    assert serving_record.serving_name == serving["name"]
    assert serving_record.serving_size_g is None
    assert serving_record.carbs_g == pytest.approx(serving["carbs"], rel=1e-3)
    assert serving_record.calories == pytest.approx(serving["kcal"], rel=1e-3)

    # Serving-size calculation on the canonical per-100g basis (the
    # calculator rounds serving values to 1 decimal place).
    scaled = nutrition_for_serving(nutrition, serving_size_g=100)
    assert scaled.food_id == food_id
    assert scaled.nutrition_source == "INDB"
    assert scaled.carbs_g == pytest.approx(round(per_100g["carbs"], 1), rel=1e-6)


def test_lookup_poha(indb_repo):
    _assert_lookup(
        indb_repo,
        label="Poha",
        expected_food_id="BFP044",
        expected_name="Poha",
        per_100g=POHA_PER_100G,
        serving=POHA_SERVING,
    )


def test_lookup_masala_dosa(indb_repo):
    _assert_lookup(
        indb_repo,
        label="Masala dosa",
        expected_food_id="ASC146",
        expected_name="Masala dosa",
        per_100g=DOSA_PER_100G,
        serving=DOSA_SERVING,
    )


def test_lookup_aloo_paratha_via_alias(indb_repo):
    _assert_lookup(
        indb_repo,
        label="Aloo paratha",
        expected_food_id="ASC098",
        expected_name="Potato parantha/paratha (Aloo ka parantha/paratha)",
        per_100g=PARATHA_PER_100G,
        serving=PARATHA_SERVING,
    )


def test_lookup_unknown_returns_none(indb_repo):
    assert indb_repo.find_food_id("Avocado toast with sourdough") is None
    assert indb_repo.find_food("Brand new dish xyz") is None


def test_scaled_serving_calculation_for_poha(indb_repo):
    nutrition = indb_repo.get_nutrition(indb_repo.find_food_id("Poha"))

    # 1 bowl of poha ~ 160.8 kcal of the per-100g basis; exercise the
    # calculator at an explicit 250 g serving (values rounded to 1 decimal).
    scaled = nutrition_for_serving(nutrition, serving_size_g=250)
    assert scaled.carbs_g == pytest.approx(round(35.048 * 2.5, 1), rel=1e-6)
    assert scaled.fat_g == pytest.approx(round(14.138 * 2.5, 1), rel=1e-6)
    assert scaled.calories == pytest.approx(round(294.526 * 2.5, 1), rel=1e-6)

    # The dataset's own per-serving values are exposed separately.
    serving = indb_repo.get_serving("BFP044")
    assert serving.calories == pytest.approx(160.781, rel=1e-3)