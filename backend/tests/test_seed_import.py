"""Tests for the INDB importer: field mapping onto the app schema."""

import pytest

from app.models.food import Food, FoodNutrition
from app.seed.constants import NUTRITION_SOURCE
from app.seed.importer import ImportError_, to_imported_dataset

from tests.synthetic_data import SYNTHETIC_FOODS, SYNTHETIC_NUTRITION


def _lookup(dataset, food_id):
    foods = {f.food_id: f for f in dataset.foods}
    nutrition = {n.food_id: n for n in dataset.nutrition}
    servings = {s.food_id: s for s in dataset.servings}
    return foods[food_id], nutrition[food_id], servings.get(food_id)


def test_import_maps_all_rows(indb_dataset):
    counts = indb_dataset.counts()
    # Whole dataset imported with no duplicate records.
    assert counts["foods"] == 1014
    assert counts["nutrition"] == 1014
    assert len({f.food_id for f in indb_dataset.foods}) == 1014
    # INDB provides a named reference serving for 917 foods.
    assert counts["servings"] == 917


def test_all_records_use_canonical_nutrition_source(indb_dataset):
    assert all(f.nutrition_source == NUTRITION_SOURCE for f in indb_dataset.foods)
    assert all(n.nutrition_source == NUTRITION_SOURCE for n in indb_dataset.nutrition)


def test_foods_are_valid_json_contract_records(indb_dataset):
    for food in indb_dataset.foods:
        Food.model_validate(food.model_dump())


def test_nutrition_records_are_non_negative(indb_dataset):
    for n in indb_dataset.nutrition:
        assert n.carbs_g_per_100g >= 0
        assert n.protein_g_per_100g >= 0
        assert n.fat_g_per_100g >= 0
        assert n.fiber_g_per_100g >= 0
        assert n.calories_per_100g >= 0


def test_poha_mapping(indb_dataset):
    food, nutrition, serving = _lookup(indb_dataset, "BFP044")
    assert food.food_name == "Poha"
    assert food.food_id == "BFP044"
    assert serving.serving_name == "bowl"
    assert nutrition.calories_per_100g == pytest.approx(294.526, rel=1e-3)
    assert nutrition.carbs_g_per_100g == pytest.approx(35.048, rel=1e-3)


def test_masala_dosa_mapping(indb_dataset):
    food, nutrition, serving = _lookup(indb_dataset, "ASC146")
    assert food.food_name == "Masala dosa"
    assert nutrition.fat_g_per_100g == pytest.approx(7.84, rel=1e-3)
    assert serving.serving_name == "dosa"
    assert serving.calories == pytest.approx(345.076, rel=1e-3)


def test_aloo_paratha_mapping_via_alias(indb_dataset):
    food, nutrition, serving = _lookup(indb_dataset, "ASC098")
    assert food.food_name == "Potato parantha/paratha (Aloo ka parantha/paratha)"
    assert nutrition.protein_g_per_100g == pytest.approx(3.698, rel=1e-3)
    assert serving.serving_name == "parantha"

    # The whole point: "Aloo paratha" must resolve to the canonical entry.
    assert indb_dataset.aliases["aloo paratha"] == "ASC098"
    assert indb_dataset.aliases["aloo ka parantha"] == "ASC098"
    assert indb_dataset.aliases["potato paratha"] == "ASC098"


def test_basic_aliases_resolve(indb_dataset):
    assert indb_dataset.aliases["poha"] == "BFP044"
    assert indb_dataset.aliases["masala dosa"] == "ASC146"
    assert indb_dataset.aliases["plain paratha"] == "ASC097"
    assert indb_dataset.aliases["chapati"] == "ASC096"
    assert indb_dataset.aliases["roti"] == "ASC096"


def test_missing_required_columns_raises():
    import pandas as pd

    frame = pd.DataFrame(
        [
            {"food_code": "X1", "food_name": "Foo", "energy_kcal": 1.0},
        ]
    )
    with pytest.raises(ImportError_):
        to_imported_dataset(frame)


def test_synthetic_records_never_use_real_dataset_aliases():
    # Guards the seed layers: synthetic fixtures must not leak aliases.
    aliases = set()
    for food in SYNTHETIC_FOODS:
        aliases.add(food.food_name.lower())
    assert "poha" not in aliases
    assert "masala dosa" not in aliases
    assert all(f.nutrition_source == "TEST_DATASET" for f in SYNTHETIC_FOODS)
    assert all(n.nutrition_source == "TEST_DATASET" for n in SYNTHETIC_NUTRITION)