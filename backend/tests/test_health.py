"""Tests for the FastAPI app wiring, incl. GET /health."""

from fastapi.testclient import TestClient

from app.main import app


def test_health_returns_ok():
    client = TestClient(app)
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_openapi_exposes_documented_endpoints():
    client = TestClient(app)
    spec = client.get("/openapi.json").json()
    paths = spec["paths"]
    assert "/health" in paths
    assert "/api/v1/foods/recognize" in paths
    assert "/api/v1/foods/analyze" in paths
    assert "post" in paths["/api/v1/foods/recognize"]
    assert "post" in paths["/api/v1/foods/analyze"]