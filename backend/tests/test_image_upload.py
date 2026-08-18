"""Endpoint tests for image upload validation on the recognition routes."""

import pytest
from fastapi.testclient import TestClient

from app.api.dependencies import get_food_analyzer
from app.main import app
from app.services.food_analyzer import FoodAnalyzer

from tests.image_helpers import (
    NOT_AN_IMAGE,
    TINY_JPEG,
    TINY_PNG,
    FakeRecognizer,
    FakeRecognizerRaising,
)


def _client_with(recognizer) -> TestClient:
    analyzer = FoodAnalyzer(recognizer=recognizer, repository=None)
    app.dependency_overrides[get_food_analyzer] = lambda: analyzer
    return TestClient(app)


def test_recognize_valid_jpeg_upload():
    client = _client_with(FakeRecognizer("Poha"))
    try:
        response = client.post(
            "/api/v1/foods/recognize",
            files={"image": ("meal.jpg", TINY_JPEG, "image/jpeg")},
        )
        assert response.status_code == 200
        assert response.json() == {"recognized_food": "Poha"}
    finally:
        app.dependency_overrides.clear()


def test_recognize_valid_png_upload():
    client = _client_with(FakeRecognizer("Masala dosa"))
    try:
        response = client.post(
            "/api/v1/foods/recognize",
            files={"image": ("meal.png", TINY_PNG, "image/png")},
        )
        assert response.status_code == 200
        assert response.json() == {"recognized_food": "Masala dosa"}
    finally:
        app.dependency_overrides.clear()


def test_recognize_rejects_invalid_image_type():
    client = _client_with(FakeRecognizer())
    try:
        response = client.post(
            "/api/v1/foods/recognize",
            files={"image": ("meal.txt", NOT_AN_IMAGE, "text/plain")},
        )
        assert response.status_code == 400
        body = response.json()
        assert body["success"] is False
        assert body["error"]["code"] == "INVALID_IMAGE"
    finally:
        app.dependency_overrides.clear()


def test_recognize_rejects_magic_bytes_not_matching_type():
    # Declared JPEG but the payload is text: sniffing must reject it.
    client = _client_with(FakeRecognizer())
    try:
        response = client.post(
            "/api/v1/foods/recognize",
            files={"image": ("meal.jpg", NOT_AN_IMAGE, "image/jpeg")},
        )
        assert response.status_code == 400
        assert response.json()["error"]["code"] == "INVALID_IMAGE"
    finally:
        app.dependency_overrides.clear()


def test_recognize_rejects_oversized_image(monkeypatch):
    import app.api.images as images

    monkeypatch.setattr(images, "MAX_IMAGE_SIZE_BYTES", 1024)
    client = _client_with(FakeRecognizer())
    try:
        response = client.post(
            "/api/v1/foods/recognize",
            files={"image": ("big.jpg", TINY_JPEG * 50, "image/jpeg")},
        )
        assert response.status_code == 413
        body = response.json()
        assert body["error"]["code"] == "IMAGE_TOO_LARGE"
        assert body["success"] is False
    finally:
        app.dependency_overrides.clear()


def test_analyze_requires_image_field():
    client = _client_with(FakeRecognizer())
    try:
        response = client.post("/api/v1/foods/analyze")
        assert response.status_code == 422
    finally:
        app.dependency_overrides.clear()


def test_recognize_maps_recognition_failure_to_502():
    client = _client_with(FakeRecognizerRaising())
    try:
        response = client.post(
            "/api/v1/foods/recognize",
            files={"image": ("meal.jpg", TINY_JPEG, "image/jpeg")},
        )
        assert response.status_code == 502
        assert response.json()["error"]["code"] == "ANALYSIS_FAILED"
    finally:
        app.dependency_overrides.clear()