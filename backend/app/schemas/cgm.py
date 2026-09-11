"""Pydantic schemas for the CGM integration API.

Follows the same conventions as ``schemas/glucose.py`` and ``schemas/meal.py``:
Pydantic v2 ``BaseModel``, ``ConfigDict(extra="forbid")`` where appropriate,
``Field`` descriptions for OpenAPI docs.
"""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, Field


# ── Provider status ────────────────────────────────────────────────────────

class CGMProviderStatus(BaseModel):
    """Current state of the CGM provider connection."""

    provider_name: str = Field(
        ...,
        description="Name of the active CGM provider (e.g. 'Mock', 'Dexcom').",
    )
    is_connected: bool = Field(
        ...,
        description="Whether the provider is reachable and has data.",
    )
    reading_count: int = Field(
        ...,
        description="Total number of readings currently held in memory.",
    )
    latest_timestamp: str | None = Field(
        default=None,
        description="ISO-8601 timestamp of the most recent reading, or null.",
    )
    connected_at: str | None = Field(
        default=None,
        description="ISO-8601 timestamp when the provider was connected.",
    )
    last_sync_at: str | None = Field(
        default=None,
        description="ISO-8601 timestamp of the last sync with the provider.",
    )


# ── Single reading ─────────────────────────────────────────────────────────

class CGMReadingResponse(BaseModel):
    """A single CGM glucose reading returned by the API."""

    timestamp: str = Field(
        ...,
        description="ISO-8601 timestamp of the reading.",
    )
    cbg: float = Field(
        ...,
        description="Continuous blood glucose in mg/dL.",
    )
    basal: float = Field(
        default=0.0,
        description="Basal insulin rate (if available).",
    )
    hr: float = Field(
        default=0.0,
        description="Heart rate in bpm (if available).",
    )
    gsr: float = Field(
        default=0.0,
        description="Galvanic skin response (if available).",
    )
    carb_input: float = Field(
        default=0.0,
        description="Carb intake in grams (if available).",
    )
    bolus: float = Field(
        default=0.0,
        description="Bolus insulin dose (if available).",
    )

    model_config = {"extra": "forbid"}


# ── History ────────────────────────────────────────────────────────────────

class CGMHistoryResponse(BaseModel):
    """A list of CGM readings returned by the history endpoint."""

    readings: list[CGMReadingResponse] = Field(
        ...,
        description="Glucose readings, newest first.",
    )
    count: int = Field(
        ...,
        description="Number of readings returned.",
    )


# ── Prediction ─────────────────────────────────────────────────────────────

class CGMPredictionResponse(BaseModel):
    """Glucose prediction derived from CGM history via the existing ONNX model."""

    prediction_30_min: float = Field(
        ...,
        description="Predicted glucose in 30 minutes (mg/dL).",
    )
    prediction_60_min: float = Field(
        ...,
        description="Predicted glucose in 60 minutes (mg/dL).",
    )
    unit: str = Field(
        default="mg/dL",
        description="Unit of the glucose values.",
    )
    readings_used: int = Field(
        ...,
        description="Number of CGM readings used for this prediction.",
    )
    iob: dict[str, Any] | None = Field(
        default=None,
        description="Deprecated: use total_iob.",
    )
    total_iob: float = Field(
        default=0.0,
        description="Total Insulin on Board in units, combining all logged doses.",
    )
