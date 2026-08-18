"""Tests for the SQLite-backed repository seeded from INDB."""

import pytest

from app.database.sqlite import SQLiteNutritionRepository
from app.models.errors import (
    FoodNotFoundError,
    NutritionDataNotFoundError,
)
from app.seed.seed import seed_database


def test_seeded_database_counts(seeded_db_path):
    repo = SQLiteNutritionRepository(seeded_db_path)
    counts = repo.counts()
    assert counts["foods"] == 1014
    assert counts["nutrition"] == 1014
    assert counts["aliases"] > 0
    assert counts["servings"] == 917


def test_no_duplicate_food_records(seeded_db_path):
    conn = SQLiteNutritionRepository(seeded_db_path)._connect()
    try:
        distinct = conn.execute(
            "SELECT COUNT(DISTINCT food_id) FROM foods"
        ).fetchone()[0]
        total = conn.execute("SELECT COUNT(*) FROM foods").fetchone()[0]
    finally:
        conn.close()
    assert distinct == total == 1014


def test_seeding_is_idempotent(indb_dataset, seeded_db_path):
    before = SQLiteNutritionRepository(seeded_db_path).counts()
    seed_database(indb_dataset, seeded_db_path)
    after = SQLiteNutritionRepository(seeded_db_path).counts()
    assert before == after


def test_get_food_returns_canonical_entry(indb_repo):
    food = indb_repo.get_food("ASC098")
    assert food.food_id == "ASC098"
    assert "Aloo" in food.food_name
    assert food.category == "Breads, Parathas & Breakfast"
    assert food.nutrition_source == "INDB"
    # INDB does not provide a serving size in grams.
    assert food.reference_serving_g is None


def test_get_food_missing_raises(indb_repo):
    with pytest.raises(FoodNotFoundError):
        indb_repo.get_food("NOPE_1")


def test_get_nutrition_returns_per_100g(indb_repo):
    nutrition = indb_repo.get_nutrition("BFP044")
    assert nutrition.food_id == "BFP044"
    assert nutrition.nutrition_source == "INDB"
    assert nutrition.calories_per_100g == pytest.approx(294.526, rel=1e-3)


def test_get_nutrition_unknown_food_raises_food_not_found(indb_repo):
    with pytest.raises(FoodNotFoundError):
        indb_repo.get_nutrition("MISSING")


def test_find_food_id_resolves_aliases(indb_repo):
    assert indb_repo.find_food_id("Poha") == "BFP044"
    assert indb_repo.find_food_id("Masala dosa") == "ASC146"
    assert indb_repo.find_food_id("Aloo paratha") == "ASC098"
    assert indb_repo.find_food_id("zzzzzz") is None


def test_find_food_id_partial_substring_fallback(indb_repo):
    # Partial "dosa" has no exact alias, but the LIKE fallback resolves it.
    food = indb_repo.find_food("dosa")
    assert food is not None
    assert "dosa" in food.food_name.lower()


def test_find_food_id_misspelled_close_match_fallback(indb_repo):
    # "alu paratha" is a typo for "Aloo paratha"; the prefix-boosted fuzzy
    # fallback must resolve to the intended food, not "Dal parantha/paratha".
    assert indb_repo.find_food_id("alu paratha") == "ASC098"
    food = indb_repo.find_food("alu paratha")
    assert food is not None
    assert food.food_id == "ASC098"
    assert "Aloo" in food.food_name


def test_exact_match_takes_precedence_over_fallback(indb_repo):
    # Exact alias still wins even when a fuzzy/substring match also exists.
    assert indb_repo.find_food_id("Masala dosa") == "ASC146"
    assert indb_repo.find_food_id("Aloo paratha") == "ASC098"
    assert indb_repo.find_food_id("Poha") == "BFP044"


def test_find_food_returns_canonical_or_none(indb_repo):
    food = indb_repo.find_food("Aloo paratha")
    assert food is not None
    assert food.food_id == "ASC098"
    assert indb_repo.find_food("not a real dish") is None


def test_get_serving_returns_named_reference(indb_repo):
    serving = indb_repo.get_serving("ASC146")
    assert serving is not None
    assert serving.serving_name == "dosa"
    assert serving.serving_size_g is None
    assert serving.calories == pytest.approx(345.076, rel=1e-3)


def test_get_serving_for_food_without_one_returns_none(indb_repo):
    # Some INDB rows carry no named serving; get_serving returns None.
    without = next(
        r["food_id"]
        for r in (
            indb_repo._connect()
            .execute(
                "SELECT f.food_id FROM foods f"
                " LEFT JOIN food_servings s ON s.food_id = f.food_id"
                " WHERE s.food_id IS NULL LIMIT 1"
            )
            .fetchall()
        )
    )
    assert indb_repo.get_serving(without) is None