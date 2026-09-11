"""Insulin logging API endpoints.

Provides CRUD for user insulin dose logs.  The logged data is consumed
by the CGM prediction pipeline to compute IOB features via the existing
``compute_iob_rapid()``, ``compute_iob_regular()``, and ``compute_iob_nph()``
functions in ``glucose_preprocessor.py``.

Endpoints
---------
GET    /api/v1/insulin/logs        → list of insulin logs
POST   /api/v1/insulin/log         → log a new insulin dose
DELETE /api/v1/insulin/log/{id}    → delete an insulin log
"""

from __future__ import annotations

import datetime as _dt

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel, Field

from ..database.sqlite import SQLiteInsulinLogRepository
from ..repositories.base import (
    INSULIN_TYPE_MAP,
    INSULIN_TYPE_NPH,
    INSULIN_TYPE_RAPID,
    INSULIN_TYPE_REGULAR,
    InsulinLogRecord,
)

router = APIRouter(
    prefix="/api/v1/insulin",
    tags=["insulin"],
)


def _get_repo() -> SQLiteInsulinLogRepository:
    return SQLiteInsulinLogRepository()


# ── Schemas ─────────────────────────────────────────────────────────────


class InsulinLogRequest(BaseModel):
    """Request body for logging an insulin dose."""

    dose_units: float = Field(
        ...,
        gt=0,
        description="Insulin dose in units.",
    )
    insulin_type: str = Field(
        default="rapid",
        description="Insulin type: rapid, regular, or nph.",
    )
    display_name: str = Field(
        default="",
        description="User-facing display name (e.g. 'Rapid-Acting (Novorapid)').",
    )
    logged_at: str = Field(
        ...,
        description="ISO-8601 timestamp when the insulin was administered.",
    )


class InsulinLogResponse(BaseModel):
    """A single insulin log entry."""

    id: int
    dose_units: float
    insulin_type: str
    display_name: str
    logged_at: str


class InsulinLogListResponse(BaseModel):
    """List of insulin log entries."""

    logs: list[InsulinLogResponse]
    count: int


class IOBResponse(BaseModel):
    """Current Insulin on Board."""

    total_iob: float = Field(
        ...,
        description="Total active insulin in units across all types.",
    )
    iob_rapid: float = Field(
        default=0.0,
        description="IOB from rapid/analogue insulin.",
    )
    iob_regular: float = Field(
        default=0.0,
        description="IOB from regular insulin.",
    )
    iob_nph: float = Field(
        default=0.0,
        description="IOB from NPH (long-acting) insulin.",
    )


# ── Endpoints ───────────────────────────────────────────────────────────


@router.get(
    "/logs",
    response_model=InsulinLogListResponse,
    summary="List insulin logs",
)
def list_insulin_logs(limit: int = 100):
    """Return recent insulin logs, newest first."""
    try:
        repo = _get_repo()
        logs = repo.get_all_logs(limit=limit)
        return InsulinLogListResponse(
            logs=[
                InsulinLogResponse(
                    id=log.id,  # type: ignore[arg-type]
                    dose_units=log.dose_units,
                    insulin_type=log.insulin_type,
                    display_name=log.display_name,
                    logged_at=log.logged_at,
                )
                for log in logs
            ],
            count=len(logs),
        )
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to retrieve insulin logs: {exc}",
        )


@router.post(
    "/log",
    response_model=InsulinLogResponse,
    status_code=201,
    summary="Log an insulin dose",
)
def log_insulin(request: InsulinLogRequest):
    """Persist a new insulin dose log entry."""
    try:
        repo = _get_repo()
        insulin_type = INSULIN_TYPE_MAP.get(
            request.insulin_type.lower(), request.insulin_type
        )
        display_name = request.display_name or request.insulin_type
        record = InsulinLogRecord(
            id=None,
            dose_units=request.dose_units,
            insulin_type=insulin_type,
            display_name=display_name,
            logged_at=request.logged_at,
        )
        row_id = repo.insert_log(record)
        print(f"[INSULIN-DEBUG] ── STEP 1: Insulin log received ──")
        print(f"[INSULIN-DEBUG]   raw_type    = '{request.insulin_type}'")
        print(f"[INSULIN-DEBUG]   mapped_type = '{insulin_type}'")
        print(f"[INSULIN-DEBUG]   display_name= '{display_name}'")
        print(f"[INSULIN-DEBUG]   dose        = {request.dose_units} U")
        print(f"[INSULIN-DEBUG]   logged_at   = {request.logged_at}")
        print(f"[INSULIN-DEBUG]   db_row_id   = {row_id}")
        print(f"[INSULIN-DEBUG]   ✓ Saved to SQLite insulin_logs table")
        return InsulinLogResponse(
            id=row_id,
            dose_units=record.dose_units,
            insulin_type=record.insulin_type,
            display_name=record.display_name,
            logged_at=record.logged_at,
        )
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to log insulin: {exc}",
        )


@router.delete(
    "/log/{log_id}",
    status_code=204,
    summary="Delete an insulin log",
)
def delete_insulin_log(log_id: int):
    """Remove an insulin log entry by id."""
    try:
        repo = _get_repo()
        repo.delete_log(log_id)
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to delete insulin log: {exc}",
        )


def _to_naive_utc(ts) -> _dt.datetime:
    """Convert any timestamp to a tz-naive UTC datetime."""
    import pandas as pd

    stamp = pd.Timestamp(ts)
    if stamp.tzinfo is not None:
        stamp = stamp.tz_convert("UTC").tz_localize(None)
    return stamp.to_pydatetime()


def _compute_iob_wallclock(
    dose_units: float,
    insulin_type: str,
    elapsed_minutes: float,
) -> float:
    """Compute IOB for a single dose using wall-clock elapsed time.

    Reuses the exact same decay logic as the CGM prediction pipeline:
    - Rapid/analogue: onset ramp (10 min) + quadratic decay, tau_end=240 min, tau_peak=75 min
    - Regular: onset plateau + quadratic decay, tau_onset=30 min, tau_end=480 min
    - NPH: Gaussian peak, tau_peak=480 min, sigma=180 min, tau_end=960 min
    """
    import math

    tau = max(0.0, elapsed_minutes)

    if insulin_type == INSULIN_TYPE_RAPID:
        tau_onset, tau_end, tau_peak = 10, 240, 75
        if tau >= tau_end:
            return 0.0
        if tau < tau_onset:
            # Linear ramp: IOB goes from 0 → dose during onset.
            s = tau / tau_onset
        else:
            s = 1 - (tau / tau_end) * (1 + (tau_end - tau) / (tau_end - tau_peak))
        return dose_units * max(0.0, s)

    if insulin_type == INSULIN_TYPE_REGULAR:
        tau_onset, tau_end = 30, 480
        if tau >= tau_end:
            return 0.0
        if tau < tau_onset:
            s = 1.0
        else:
            s = 1.0 - ((tau - tau_onset) / (tau_end - tau_onset)) ** 2
        return dose_units * max(0.0, s)

    if insulin_type == INSULIN_TYPE_NPH:
        tau_peak, sigma, tau_end = 480, 180, 960
        if tau >= tau_end:
            return 0.0
        s = math.exp(-((tau - tau_peak) ** 2) / (2 * sigma**2))
        return dose_units * s

    # Unknown type — treat as rapid.
    tau_end, tau_peak = 240, 75
    if tau >= tau_end:
        return 0.0
    s = 1 - (tau / tau_end) * (1 + (tau_end - tau) / (tau_end - tau_peak))
    return dose_units * max(0.0, s)


@router.get(
    "/iob",
    response_model=IOBResponse,
    summary="Get current Insulin on Board",
)
def get_iob():
    """Compute current IOB from all stored insulin logs using wall-clock decay.

    This is the single source of truth for IOB, used by both the Home and
    CGM screens.  Each dose is decayed from its logged timestamp using the
    type-specific pharmacokinetic model (rapid, regular, NPH).
    """
    try:
        repo = _get_repo()
        logs = repo.get_all_logs(limit=1000)
        now_utc = _dt.datetime.now(_dt.timezone.utc)
        now_naive = _to_naive_utc(now_utc)

        iob_rapid = 0.0
        iob_regular = 0.0
        iob_nph = 0.0

        for log in logs:
            try:
                dose_ts = _to_naive_utc(log.logged_at)
                elapsed_min = (now_naive - dose_ts).total_seconds() / 60.0
                iob = _compute_iob_wallclock(
                    log.dose_units, log.insulin_type, elapsed_min,
                )
                if log.insulin_type == INSULIN_TYPE_RAPID:
                    iob_rapid += iob
                elif log.insulin_type == INSULIN_TYPE_REGULAR:
                    iob_regular += iob
                elif log.insulin_type == INSULIN_TYPE_NPH:
                    iob_nph += iob
                else:
                    iob_rapid += iob
            except Exception:
                continue

        total_iob = round(iob_rapid + iob_regular + iob_nph, 3)
        print(f"[IOB-ENDPOINT] rapid={iob_rapid:.3f} regular={iob_regular:.3f} "
              f"nph={iob_nph:.3f} total={total_iob:.3f}")

        return IOBResponse(
            total_iob=total_iob,
            iob_rapid=round(iob_rapid, 3),
            iob_regular=round(iob_regular, 3),
            iob_nph=round(iob_nph, 3),
        )
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to compute IOB: {exc}",
        )
