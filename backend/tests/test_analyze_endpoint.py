"""End-to-end tests for POST /api/v1/foods/analyze (Gemini fully mocked).

Overrides the app's ``get_food_analyzer`` dependency with a pipeline backed by
the real seeded INDB repository plus a fake recognizer, then exercises the full
workflow over HTTP: image upload -> recognition -> INDB match -> nutrition.
"""

import pytest
from fastapi.testclient import TestClient

from app.api.dependencies import get_food_analyzer
from app.main import app
from app.services.food_analyzer import FoodAnalyzer

from tests.image_helpers import TINY_JPEG, FakeRecognizer


@pytest.fixture(autouse=True)
def _clean_overrides():
    yield
    app.dependency_overrides.clear()


def _override(indb_repo, food_name=None, food_names=None):
    def _factory():
        return FoodAnalyzer(
            recognizer=FakeRecognizer(food_name=food_name, food_names=food_names),
            repository=indb_repo,
        )

    app.dependency_overrides[get_food_analyzer] = _factory


# ---------------------------------------------------------------------------
# Single food (backward-compatible)
# ---------------------------------------------------------------------------


def test_analyze_endpoint_returns_matched_nutrition(indb_repo):
    _override(indb_repo, "Poha")
    response = TestClient(app).post(
        "/api/v1/foods/analyze",
        files={"image": ("meal.jpg", TINY_JPEG, "image/jpeg")},
    )
    assert response.status_code == 200
    body = response.json()
    # Unified response format: always a list
    assert "foods" in body
    assert len(body["foods"]) == 1
    food = body["foods"][0]
    assert food["recognized_food"] == "Poha"
    assert food["matched"] is True
    assert food["food_id"] == "BFP044"
    assert food["nutrition"]["carb_g"] == pytest.approx(35.048, rel=1e-3)
    assert food["nutrition"]["nutrition_source"] == "INDB"
    # total_nutrition equals the single food
    assert body["total_nutrition"]["carb_g"] == pytest.approx(35.048, rel=1e-3)


def test_analyze_endpoint_alias_food(indb_repo):
    _override(indb_repo, "Aloo paratha")
    response = TestClient(app).post(
        "/api/v1/foods/analyze",
        files={"image": ("meal.jpg", TINY_JPEG, "image/jpeg")},
    )
    assert response.status_code == 200
    body = response.json()
    assert len(body["foods"]) == 1
    assert body["foods"][0]["matched"] is True
    assert body["foods"][0]["food_id"] == "ASC098"


def test_analyze_endpoint_food_not_found(indb_repo):
    _override(indb_repo, "Rajma Chawal")
    response = TestClient(app).post(
        "/api/v1/foods/analyze",
        files={"image": ("meal.jpg", TINY_JPEG, "image/jpeg")},
    )
    assert response.status_code == 200
    body = response.json()
    assert len(body["foods"]) == 1
    assert body["foods"][0]["recognized_food"] == "Rajma Chawal"
    assert body["foods"][0]["matched"] is False
    # total_nutrition is omitted when None (response_model_exclude_none=True)
    assert "total_nutrition" not in body


# ---------------------------------------------------------------------------
# Multiple foods
# ---------------------------------------------------------------------------


def test_analyze_endpoint_multi_food_all_matched(indb_repo):
    _override(indb_repo, food_names=["Poha", "Rice", "Tea"])
    response = TestClient(app).post(
        "/api/v1/foods/analyze",
        files={"image": ("meal.jpg", TINY_JPEG, "image/jpeg")},
    )
    assert response.status_code == 200
    body = response.json()
    assert len(body["foods"]) == 3
    for f in body["foods"]:
        assert f["matched"] is True
    # Verify aggregation
    assert body["total_nutrition"]["carb_g"] == pytest.approx(
        35.048 + 32.93 + 2.582, rel=1e-3
    )
    assert body["total_nutrition"]["energy_kcal"] == pytest.approx(
        294.526 + 195.737 + 16.144, rel=1e-3
    )


def test_analyze_endpoint_multi_food_partial_match(indb_repo):
    _override(indb_repo, food_names=["Poha", "Rajma Chawal"])
    response = TestClient(app).post(
        "/api/v1/foods/analyze",
        files={"image": ("meal.jpg", TINY_JPEG, "image/jpeg")},
    )
    assert response.status_code == 200
    body = response.json()
    assert len(body["foods"]) == 2
    assert body["foods"][0]["matched"] is True
    assert body["foods"][1]["matched"] is False
    # total only includes matched items
    assert body["total_nutrition"]["carb_g"] == pytest.approx(35.048, rel=1e-3)


# ---------------------------------------------------------------------------
# Recognize endpoint
# ---------------------------------------------------------------------------


def test_recognize_endpoint_single_food(indb_repo):
    _override(indb_repo, "Poha")
    response = TestClient(app).post(
        "/api/v1/foods/recognize",
        files={"image": ("meal.jpg", TINY_JPEG, "image/jpeg")},
    )
    assert response.status_code == 200
    body = response.json()
    assert "foods" in body
    assert len(body["foods"]) == 1
    assert body["foods"][0]["name"] == "Poha"


def test_recognize_endpoint_multi_food(indb_repo):
    _override(indb_repo, food_names=["Poha", "Rice", "Roti"])
    response = TestClient(app).post(
        "/api/v1/foods/recognize",
        files={"image": ("meal.jpg", TINY_JPEG, "image/jpeg")},
    )
    assert response.status_code == 200
    body = response.json()
    assert len(body["foods"]) == 3
    names = [f["name"] for f in body["foods"]]
    assert names == ["Poha", "Rice", "Roti"]
