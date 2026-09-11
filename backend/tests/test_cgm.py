"""Tests for the CGM integration module.

Covers:
- MockCGMProvider behaviour
- CGMService (status, latest reading, history, prediction)
- API endpoints via TestClient
- Insufficient-history error path
- Reuse of existing prediction pipeline
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services.cgm_provider import (
    CGMProvider,
    CGMReading,
    MockCGMProvider,
    set_cgm_provider,
)
from app.services.cgm_service import CGMService


# ── Helpers ─────────────────────────────────────────────────────────────────


class FakeProvider(CGMProvider):
    """Deterministic provider for unit tests."""

    def __init__(self, readings: list[CGMReading] | None = None) -> None:
        now = datetime.now(timezone.utc)
        if readings is None:
            readings = [
                CGMReading(
                    timestamp=now - timedelta(minutes=5 * i),
                    cbg=100.0 + i,
                )
                for i in range(30)
            ]
        self._readings = readings

    @property
    def name(self) -> str:
        return "Fake"

    @property
    def is_available(self) -> bool:
        return True

    def get_latest_reading(self) -> CGMReading:
        return self._readings[0]

    def get_readings(
        self,
        since: datetime | None = None,
        limit: int = 288,
    ) -> list[CGMReading]:
        if since is None:
            return self._readings[:limit]
        return [r for r in self._readings if r.timestamp >= since][:limit]


# ── MockCGMProvider unit tests ─────────────────────────────────────────────


class TestMockCGMProvider:
    def test_name(self):
        provider = MockCGMProvider()
        assert provider.name == "Mock"

    def test_is_available(self):
        provider = MockCGMProvider()
        assert provider.is_available is True

    def test_generates_288_readings(self):
        provider = MockCGMProvider()
        readings = provider.get_readings()
        assert len(readings) == 288

    def test_latest_reading_exists(self):
        provider = MockCGMProvider()
        latest = provider.get_latest_reading()
        assert isinstance(latest, CGMReading)
        assert latest.cbg > 0

    def test_readings_newest_first(self):
        provider = MockCGMProvider()
        readings = provider.get_readings(limit=10)
        timestamps = [r.timestamp for r in readings]
        assert timestamps == sorted(timestamps, reverse=True)

    def test_limit_reduces_count(self):
        provider = MockCGMProvider()
        readings = provider.get_readings(limit=5)
        assert len(readings) == 5

    def test_since_filters_readings(self):
        provider = MockCGMProvider()
        all_readings = provider.get_readings()
        cutoff = all_readings[5].timestamp
        filtered = provider.get_readings(since=cutoff)
        assert all(r.timestamp >= cutoff for r in filtered)

    def test_reading_has_required_fields(self):
        provider = MockCGMProvider()
        reading = provider.get_latest_reading()
        assert reading.timestamp is not None
        assert isinstance(reading.cbg, float)
        assert reading.cbg > 0

    def test_to_dict_keys(self):
        reading = CGMReading(
            timestamp=datetime(2025, 1, 1, tzinfo=timezone.utc),
            cbg=120.0,
        )
        d = reading.to_dict()
        assert "timestamp" in d
        assert "cbg" in d
        assert "basal" in d
        assert "hr" in d
        assert "gsr" in d
        assert "carbInput" in d
        assert "bolus" in d


# ── CGMService unit tests ──────────────────────────────────────────────────


class TestCGMService:
    def test_status_returns_required_fields(self):
        provider = FakeProvider()
        service = CGMService(provider=provider)
        status = service.get_status()
        assert "provider_name" in status
        assert "is_connected" in status
        assert "reading_count" in status
        assert "latest_timestamp" in status
        assert status["provider_name"] == "Fake"
        assert status["is_connected"] is True
        assert status["reading_count"] == 30

    def test_get_latest_reading(self):
        provider = FakeProvider()
        service = CGMService(provider=provider)
        reading = service.get_latest_reading()
        assert isinstance(reading, CGMReading)
        assert reading.cbg == 100.0

    def test_get_history(self):
        provider = FakeProvider()
        service = CGMService(provider=provider)
        history = service.get_history(limit=10)
        assert len(history) == 10

    def test_predict_from_history_uses_existing_pipeline(self):
        """Verify that prediction goes through the existing ONNX model."""
        provider = FakeProvider()
        service = CGMService(provider=provider)
        result = service.predict_from_history()
        assert "prediction_30_min" in result
        assert "prediction_60_min" in result
        assert result["unit"] == "mg/dL"
        assert result["readings_used"] == 30
        assert isinstance(result["prediction_30_min"], float)
        assert isinstance(result["prediction_60_min"], float)

    def test_insufficient_readings_raises_value_error(self):
        now = datetime.now(timezone.utc)
        few_readings = [
            CGMReading(timestamp=now - timedelta(minutes=5 * i), cbg=100.0)
            for i in range(10)
        ]
        provider = FakeProvider(readings=few_readings)
        service = CGMService(provider=provider)
        with pytest.raises(ValueError, match="At least 24"):
            service.predict_from_history()

    def test_readings_to_dataframe_has_expected_columns(self):
        provider = FakeProvider()
        service = CGMService(provider=provider)
        readings = provider.get_readings(limit=5)
        df = service._readings_to_dataframe(readings)
        assert "timestamp" in df.columns
        assert "cbg" in df.columns
        assert "basal" in df.columns
        assert "hr" in df.columns
        assert "gsr" in df.columns
        assert "carbInput" in df.columns
        assert "bolus" in df.columns


# ── API endpoint tests ──────────────────────────────────────────────────────


class TestCGMEndpoints:
    def setup_method(self):
        self.client = TestClient(app)
        # Install a deterministic provider for all endpoint tests
        set_cgm_provider(FakeProvider())

    def test_status_endpoint(self):
        response = self.client.get("/api/v1/cgm/status")
        assert response.status_code == 200
        body = response.json()
        assert body["provider_name"] == "Fake"
        assert body["is_connected"] is True

    def test_latest_reading_endpoint(self):
        response = self.client.get("/api/v1/cgm/reading/latest")
        assert response.status_code == 200
        body = response.json()
        assert "cbg" in body
        assert "timestamp" in body
        assert body["cbg"] > 0

    def test_readings_endpoint(self):
        response = self.client.get("/api/v1/cgm/readings?limit=5")
        assert response.status_code == 200
        body = response.json()
        assert body["count"] == 5
        assert len(body["readings"]) == 5

    def test_predict_endpoint(self):
        response = self.client.post("/api/v1/cgm/predict")
        assert response.status_code == 200
        body = response.json()
        assert "prediction_30_min" in body
        assert "prediction_60_min" in body
        assert body["unit"] == "mg/dL"
        assert body["readings_used"] == 30

    def test_predict_insufficient_history_returns_400(self):
        now = datetime.now(timezone.utc)
        few = [
            CGMReading(timestamp=now - timedelta(minutes=5 * i), cbg=100.0)
            for i in range(5)
        ]
        set_cgm_provider(FakeProvider(readings=few))
        response = self.client.post("/api/v1/cgm/predict")
        assert response.status_code == 400
        assert "At least 24" in response.json()["detail"]

    def test_readings_endpoint_respects_limit(self):
        response = self.client.get("/api/v1/cgm/readings?limit=3")
        assert response.status_code == 200
        body = response.json()
        assert body["count"] == 3


# ── OpenAPI spec check ─────────────────────────────────────────────────────


class TestCGMOpenAPI:
    def test_cgm_endpoints_in_spec(self):
        client = TestClient(app)
        spec = client.get("/openapi.json").json()
        paths = spec["paths"]
        assert "/api/v1/cgm/status" in paths
        assert "/api/v1/cgm/reading/latest" in paths
        assert "/api/v1/cgm/readings" in paths
        assert "/api/v1/cgm/predict" in paths


# ── Insulin API tests ─────────────────────────────────────────────────────


class TestInsulinAPI:
    def setup_method(self):
        self.client = TestClient(app)

    def test_log_and_list_insulin(self):
        # Log an insulin dose.
        response = self.client.post(
            "/api/v1/insulin/log",
            json={
                "dose_units": 4.5,
                "insulin_type": "rapid",
                "logged_at": "2026-01-01T12:00:00",
            },
        )
        assert response.status_code == 201
        body = response.json()
        assert body["dose_units"] == 4.5
        assert body["insulin_type"] == "rapid"
        log_id = body["id"]

        # List logs.
        response = self.client.get("/api/v1/insulin/logs")
        assert response.status_code == 200
        data = response.json()
        assert data["count"] >= 1
        assert any(l["id"] == log_id for l in data["logs"])

        # Delete it.
        response = self.client.delete(f"/api/v1/insulin/log/{log_id}")
        assert response.status_code == 204

    def test_insulin_endpoints_in_spec(self):
        spec = self.client.get("/openapi.json").json()
        paths = spec["paths"]
        assert "/api/v1/insulin/logs" in paths
        assert "/api/v1/insulin/log" in paths


# ── Insulin merge in CGMService ────────────────────────────────────────────


class TestCGMInsulinMerge:
    """Verify that _merge_insulin_data correctly assigns insulin doses
    to the nearest preceding CGM interval."""

    def test_insulin_rapid_goes_to_bolus(self, tmp_path):
        from app.repositories.base import InsulinLogRecord, INSULIN_TYPE_RAPID
        from app.database.sqlite import SQLiteInsulinLogRepository

        db_path = tmp_path / "insulin_test.db"
        repo = SQLiteInsulinLogRepository(db_path)
        repo.insert_log(InsulinLogRecord(
            id=None, dose_units=5.0, insulin_type=INSULIN_TYPE_RAPID,
            logged_at="2026-01-01T12:02:00",
        ))

        service = CGMService(insulin_repository=repo)

        import pandas as pd
        df = pd.DataFrame({
            "cbg": [120.0, 125.0, 130.0],
            "basal": [0.0, 0.0, 0.0],
            "hr": [70.0, 70.0, 70.0],
            "gsr": [5.0, 5.0, 5.0],
            "carbInput": [0.0, 0.0, 0.0],
            "bolus": [0.0, 0.0, 0.0],
            "timestamp": pd.to_datetime([
                "2026-01-01T11:55:00",
                "2026-01-01T12:00:00",
                "2026-01-01T12:05:00",
            ]),
        })

        result = service._merge_insulin_data(df)

        # Dose at 12:02 should go to the 12:00 interval.
        assert result.loc[1, "bolus"] == 5.0
        assert result.loc[0, "bolus"] == 0.0
        assert result.loc[2, "bolus"] == 0.0

    def test_insulin_nph_goes_to_basal(self, tmp_path):
        from app.repositories.base import InsulinLogRecord, INSULIN_TYPE_NPH
        from app.database.sqlite import SQLiteInsulinLogRepository

        db_path = tmp_path / "insulin_nph_test.db"
        repo = SQLiteInsulinLogRepository(db_path)
        repo.insert_log(InsulinLogRecord(
            id=None, dose_units=10.0, insulin_type=INSULIN_TYPE_NPH,
            logged_at="2026-01-01T12:02:00",
        ))

        service = CGMService(insulin_repository=repo)

        import pandas as pd
        df = pd.DataFrame({
            "cbg": [120.0, 125.0],
            "basal": [0.0, 0.0],
            "hr": [70.0, 70.0],
            "gsr": [5.0, 5.0],
            "carbInput": [0.0, 0.0],
            "bolus": [0.0, 0.0],
            "timestamp": pd.to_datetime([
                "2026-01-01T12:00:00",
                "2026-01-01T12:05:00",
            ]),
        })

        result = service._merge_insulin_data(df)

        assert result.loc[0, "basal"] == 10.0
        assert result.loc[0, "bolus"] == 0.0
