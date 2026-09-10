"""Food analyzer pipeline tests: matching against the real seeded INDB data.

Uses the ``indb_repo`` fixture (real INDB seeded SQLite repository). Gemini is
always replaced with ``FakeRecognizer`` so no API is called.
"""

import pytest

from app.services.food_analyzer import FoodAnalyzer, aggregate_nutrition

from tests.image_helpers import FakeRecognizer, TINY_JPEG


def _analyzer(indb_repo, food_name=None, food_names=None):
    return FoodAnalyzer(
        recognizer=FakeRecognizer(food_name=food_name, food_names=food_names),
        repository=indb_repo,
    )


# ---------------------------------------------------------------------------
# Single food tests (backward-compatible)
# ---------------------------------------------------------------------------


def test_analyze_exact_match_poha(indb_repo):
    result = _analyzer(indb_repo, "Poha").analyze(TINY_JPEG, "image/jpeg")
    assert len(result.foods) == 1
    f = result.foods[0]
    assert f.matched is True
    assert f.recognized_food == "Poha"
    assert f.food_id == "BFP044"
    assert f.nutrition["carb_g"] == pytest.approx(35.048, rel=1e-3)
    assert f.nutrition["nutrition_source"] == "INDB"
    assert f.nutrition["basis"] == "per_100g"
    assert f.message is None


def test_analyze_single_food_total_equals_item(indb_repo):
    result = _analyzer(indb_repo, "Poha").analyze(TINY_JPEG, "image/jpeg")
    assert len(result.foods) == 1
    # total_nutrition must equal the single food's nutrition
    assert result.total_nutrition is not None
    assert result.total_nutrition["carb_g"] == pytest.approx(35.048, rel=1e-3)
    assert result.total_nutrition["protein_g"] == pytest.approx(6.085, rel=1e-3)
    assert result.total_nutrition["fat_g"] == pytest.approx(14.138, rel=1e-3)
    assert result.total_nutrition["fibre_g"] == pytest.approx(3.716, rel=1e-3)
    assert result.total_nutrition["energy_kcal"] == pytest.approx(294.526, rel=1e-3)


def test_analyze_normalized_match_aloo_paratha(indb_repo):
    result = _analyzer(indb_repo, "aloo paratha").analyze(TINY_JPEG, "image/jpeg")
    assert len(result.foods) == 1
    f = result.foods[0]
    assert f.matched is True
    assert f.food_id == "ASC098"
    assert "Aloo" in f.food_name


def test_analyze_food_not_found(indb_repo):
    result = _analyzer(indb_repo, "Rajma Chawal").analyze(TINY_JPEG, "image/jpeg")
    assert len(result.foods) == 1
    f = result.foods[0]
    assert f.matched is False
    assert f.recognized_food == "Rajma Chawal"
    assert f.message == "Food not found in nutrition database"
    assert f.food_id is None
    assert f.nutrition is None
    assert result.total_nutrition is None


def test_lookup_matches_additional_indb_fields(indb_repo):
    result = _analyzer(indb_repo, "Masala dosa").lookup("Masala dosa")
    assert result.matched is True
    nutrition = result.nutrition
    assert set(nutrition) == {
        "carb_g", "protein_g", "fat_g", "fibre_g", "energy_kcal",
        "basis", "nutrition_source",
    }
    assert nutrition["energy_kcal"] == pytest.approx(164.585, rel=1e-3)


# ---------------------------------------------------------------------------
# Multiple food tests
# ---------------------------------------------------------------------------


def test_analyze_multiple_foods_all_matched(indb_repo):
    result = _analyzer(
        indb_repo, food_names=["Poha", "Rice", "Tea"]
    ).analyze(TINY_JPEG, "image/jpeg")

    assert len(result.foods) == 3
    for f in result.foods:
        assert f.matched is True

    # Verify individual items
    assert result.foods[0].food_id == "BFP044"  # Poha
    assert result.foods[1].food_id == "ASC126"  # Rice
    assert result.foods[2].food_id == "ASC001"  # Tea

    # Verify aggregation
    assert result.total_nutrition is not None
    assert result.total_nutrition["carb_g"] == pytest.approx(
        35.048 + 32.93 + 2.582, rel=1e-3
    )
    assert result.total_nutrition["protein_g"] == pytest.approx(
        6.085 + 5.753 + 0.388, rel=1e-3
    )
    assert result.total_nutrition["fat_g"] == pytest.approx(
        14.138 + 4.317 + 0.532, rel=1e-3
    )
    assert result.total_nutrition["fibre_g"] == pytest.approx(
        3.716 + 2.134 + 0.0, rel=1e-3
    )
    assert result.total_nutrition["energy_kcal"] == pytest.approx(
        294.526 + 195.737 + 16.144, rel=1e-3
    )


def test_analyze_multiple_foods_partial_match(indb_repo):
    result = _analyzer(
        indb_repo, food_names=["Poha", "Rajma Chawal"]
    ).analyze(TINY_JPEG, "image/jpeg")

    assert len(result.foods) == 2
    assert result.foods[0].matched is True   # Poha
    assert result.foods[1].matched is False  # Rajma Chawal

    # total_nutrition includes only Poha
    assert result.total_nutrition is not None
    assert result.total_nutrition["carb_g"] == pytest.approx(35.048, rel=1e-3)
    assert result.total_nutrition["energy_kcal"] == pytest.approx(294.526, rel=1e-3)


def test_analyze_multiple_foods_none_matched(indb_repo):
    result = _analyzer(
        indb_repo, food_names=["Rajma Chawal", "Avocado toast"]
    ).analyze(TINY_JPEG, "image/jpeg")

    assert len(result.foods) == 2
    assert result.foods[0].matched is False
    assert result.foods[1].matched is False
    assert result.total_nutrition is None


def test_analyze_two_foods_aggregation_math(indb_repo):
    result = _analyzer(
        indb_repo, food_names=["Poha", "Masala dosa"]
    ).analyze(TINY_JPEG, "image/jpeg")

    assert len(result.foods) == 2
    assert result.total_nutrition is not None

    expected_carbs = 35.048 + 19.567
    expected_kcal = 294.526 + 164.585
    assert result.total_nutrition["carb_g"] == pytest.approx(expected_carbs, rel=1e-3)
    assert result.total_nutrition["energy_kcal"] == pytest.approx(expected_kcal, rel=1e-3)


# ---------------------------------------------------------------------------
# recognize() tests (no nutrition lookup)
# ---------------------------------------------------------------------------


def test_recognize_returns_list(indb_repo):
    result = _analyzer(indb_repo, "Poha").recognize(TINY_JPEG, "image/jpeg")
    assert len(result.foods) == 1
    assert result.foods[0].recognized_food == "Poha"
    assert result.foods[0].matched is False  # recognize() does not look up nutrition
    assert result.total_nutrition is None


def test_recognize_multi_food_returns_list(indb_repo):
    result = _analyzer(
        indb_repo, food_names=["Poha", "Rice"]
    ).recognize(TINY_JPEG, "image/jpeg")
    assert len(result.foods) == 2
    assert result.foods[0].recognized_food == "Poha"
    assert result.foods[1].recognized_food == "Rice"


# ---------------------------------------------------------------------------
# aggregate_nutrition unit tests
# ---------------------------------------------------------------------------


def test_aggregate_nutrition_empty_list():
    assert aggregate_nutrition([]) is None


def test_aggregate_nutrition_no_matches():
    from app.services.food_analyzer import FoodAnalysisResult
    items = [
        FoodAnalysisResult(recognized_food="X", matched=False),
        FoodAnalysisResult(recognized_food="Y", matched=False),
    ]
    assert aggregate_nutrition(items) is None


def test_aggregate_nutrition_partial_matches():
    from app.services.food_analyzer import FoodAnalysisResult
    items = [
        FoodAnalysisResult(
            recognized_food="A", matched=True,
            nutrition={"carb_g": 10, "protein_g": 5, "fat_g": 2, "fibre_g": 1, "energy_kcal": 100},
        ),
        FoodAnalysisResult(recognized_food="B", matched=False),
    ]
    agg = aggregate_nutrition(items)
    assert agg is not None
    assert agg["carb_g"] == 10.0
    assert agg["energy_kcal"] == 100.0
