"""Food analyzer pipeline tests: matching against the real seeded INDB data.

Uses the ``indb_repo`` fixture (real INDB seeded SQLite repository). Gemini is
always replaced with ``FakeRecognizer`` so no API is called.
"""

import pytest

from app.services.food_analyzer import FoodAnalyzer

from tests.image_helpers import FakeRecognizer, TINY_JPEG


def _analyzer(indb_repo, food_name):
    return FoodAnalyzer(recognizer=FakeRecognizer(food_name), repository=indb_repo)


def test_analyze_exact_match_poha(indb_repo):
    result = _analyzer(indb_repo, "Poha").analyze(TINY_JPEG, "image/jpeg")
    assert result.matched is True
    assert result.recognized_food == "Poha"
    assert result.food_id == "BFP044"
    assert result.nutrition["carb_g"] == pytest.approx(35.048, rel=1e-3)
    assert result.nutrition["nutrition_source"] == "INDB"
    assert result.nutrition["basis"] == "per_100g"
    assert result.message is None


def test_analyze_normalized_match_aloo_paratha(indb_repo):
    # "aloo paratha" is a normalized alias of the canonical INDB name
    # "Potato parantha/paratha (Aloo ka parantha/paratha)".
    result = _analyzer(indb_repo, "aloo paratha").analyze(TINY_JPEG, "image/jpeg")
    assert result.matched is True
    assert result.food_id == "ASC098"
    assert "Aloo" in result.food_name


def test_analyze_food_not_found(indb_repo):
    result = _analyzer(indb_repo, "Rajma Chawal").analyze(TINY_JPEG, "image/jpeg")
    assert result.matched is False
    assert result.recognized_food == "Rajma Chawal"
    assert result.message == "Food not found in nutrition database"
    assert result.food_id is None
    assert result.nutrition is None


def test_lookup_matches_additional_indb_fields(indb_repo):
    result = _analyzer(indb_repo, "Masala dosa").lookup("Masala dosa")
    assert result.matched is True
    nutrition = result.nutrition
    assert set(nutrition) == {
        "carb_g", "protein_g", "fat_g", "fibre_g", "energy_kcal",
        "basis", "nutrition_source",
    }
    assert nutrition["energy_kcal"] == pytest.approx(164.585, rel=1e-3)