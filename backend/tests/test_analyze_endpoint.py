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


def _override(indb_repo, food_name):
    def _factory():
        return FoodAnalyzer(
            recognizer=FakeRecognizer(food_name), repository=indb_repo
        )

    app.dependency_overrides[get_food_analyzer] = _factory


def test_analyze_endpoint_returns_matched_nutrition(indb_repo):
    _override(indb_repo, "Poha")
    response = TestClient(app).post(
        "/api/v1/foods/analyze",
        files={"image": ("meal.jpg", TINY_JPEG, "image/jpeg")},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["recognized_food"] == "Poha"
    assert body["matched"] is True
    assert body["food_id"] == "BFP044"
    assert body["nutrition"]["carb_g"] == pytest.approx(35.048, rel=1e-3)
    assert body["nutrition"]["nutrition_source"] == "INDB"


def test_analyze_endpoint_alias_food(indb_repo):
    _override(indb_repo, "Aloo paratha")
    response = TestClient(app).post(
        "/api/v1/foods/analyze",
        files={"image": ("meal.jpg", TINY_JPEG, "image/jpeg")},
    )
    assert response.status_code == 200
    body = response.json()
    assert body["matched"] is True
    assert body["food_id"] == "ASC098"


def test_analyze_endpoint_food_not_found(indb_repo):
    _override(indb_repo, "Rajma Chawal")
    response = TestClient(app).post(
        "/api/v1/foods/analyze",
        files={"image": ("meal.jpg", TINY_JPEG, "image/jpeg")},
    )
    assert response.status_code == 200
    body = response.json()
    assert body == {
        "recognized_food": "Rajma Chawal",
        "matched": False,
        "message": "Food not found in nutrition database",
    }