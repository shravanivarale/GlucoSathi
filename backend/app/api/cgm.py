"""CGM integration API endpoints.

Provides connection status, glucose readings, prediction, and connection
management via the CGM service layer.  Follows the same error-handling
and schema conventions as ``api/glucose.py``.

Endpoints
---------
GET    /api/v1/cgm/status            → CGMProviderStatus
GET    /api/v1/cgm/reading/latest    → CGMReadingResponse
GET    /api/v1/cgm/readings          → CGMHistoryResponse
POST   /api/v1/cgm/predict           → CGMPredictionResponse
POST   /api/v1/cgm/connect           → CGMProviderStatus
POST   /api/v1/cgm/disconnect        → CGMProviderStatus
"""

from __future__ import annotations

from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException

from ..database.sqlite import SQLiteCGMRepository, SQLiteInsulinLogRepository
from ..schemas.cgm import (
    CGMHistoryResponse,
    CGMPredictionResponse,
    CGMProviderStatus,
    CGMReadingResponse,
)
from ..services.cgm_service import CGMService

router = APIRouter(
    prefix="/api/v1/cgm",
    tags=["cgm"],
)


def _get_service() -> CGMService:
    """Resolve the CGM service with the SQLite repository and insulin logs."""
    return CGMService(
        repository=SQLiteCGMRepository(),
        insulin_repository=SQLiteInsulinLogRepository(),
    )


# ── Status ──────────────────────────────────────────────────────────────

@router.get(
    "/status",
    response_model=CGMProviderStatus,
    summary="CGM connection status",
)
def get_cgm_status():
    """Return the current CGM provider connection status."""
    import datetime as _dt
    _t0 = _dt.datetime.now(_dt.timezone.utc)
    print(f"[CGM-DEBUG] ═══ /api/v1/cgm/status REACHED at {_t0.isoformat()} ═══")
    try:
        service = _get_service()
        print(f"[CGM-DEBUG]   Provider: {service.provider.name}, "
              f"available={service.provider.is_available}")
        status = service.get_status()
        print(f"[CGM-DEBUG]   Status: is_connected={status.get('is_connected')}, "
              f"reading_count={status.get('reading_count')}")
        _t1 = _dt.datetime.now(_dt.timezone.utc)
        print(f"[CGM-DEBUG] ═══ /status completed in {(_t1 - _t0).total_seconds():.2f}s ═══")
        return CGMProviderStatus(**status)
    except Exception as exc:
        print(f"[CGM-DEBUG] ❌ /status FAILED: {exc}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to retrieve CGM status: {exc}",
        )


# ── Latest reading ──────────────────────────────────────────────────────

@router.get(
    "/reading/latest",
    response_model=CGMReadingResponse,
    summary="Latest CGM glucose reading",
)
def get_latest_reading():
    """Return the single most recent CGM glucose reading."""
    try:
        import datetime as _dt
        now = _dt.datetime.now(_dt.timezone.utc)
        print(f"[CGM-REFRESH] ── get_latest_reading called at {now.isoformat()} ──")
        service = _get_service()
        reading = service.get_latest_reading()
        print(f"[CGM-REFRESH]   Returned: ts={reading.timestamp.isoformat()}, "
              f"cbg={reading.cbg}")

        # Update last_sync_at in the database so the Profile screen
        # shows the same sync time as the CGM Status screen.
        from ..repositories.base import CGMConnectionRecord
        existing_conn = service.get_connection_state(service.provider.name)
        service.persist_connection(
            CGMConnectionRecord(
                provider_name=service.provider.name,
                status="connected",
                connected_at=(existing_conn.connected_at
                              if existing_conn else now.isoformat()),
                last_sync_at=now.isoformat(),
            )
        )
        print(f"[CGM] Connection last_sync_at updated: {now.isoformat()}")

        return CGMReadingResponse(
            timestamp=reading.timestamp.isoformat(),
            cbg=reading.cbg,
            basal=reading.basal,
            hr=reading.hr,
            gsr=reading.gsr,
            carb_input=reading.carb_input,
            bolus=reading.bolus,
        )
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to retrieve latest reading: {exc}",
        )


# ── History ─────────────────────────────────────────────────────────────

@router.get(
    "/readings",
    response_model=CGMHistoryResponse,
    summary="CGM glucose history",
)
def get_readings(limit: int = 288):
    """Return recent CGM readings, newest first.

    Parameters
    ----------
    limit:
        Maximum number of readings (default 288 = 24 h at 5-min intervals).
    """
    try:
        service = _get_service()
        readings = service.get_history(limit=limit)
        return CGMHistoryResponse(
            readings=[
                CGMReadingResponse(
                    timestamp=r.timestamp.isoformat(),
                    cbg=r.cbg,
                    basal=r.basal,
                    hr=r.hr,
                    gsr=r.gsr,
                    carb_input=r.carb_input,
                    bolus=r.bolus,
                )
                for r in readings
            ],
            count=len(readings),
        )
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to retrieve CGM history: {exc}",
        )


# ── Prediction ──────────────────────────────────────────────────────────

@router.post(
    "/predict",
    response_model=CGMPredictionResponse,
    summary="Predict glucose using CGM history",
)
def predict_from_cgm():
    """Run the existing ONNX glucose model on CGM history."""
    try:
        import datetime as _dt
        now = _dt.datetime.now(_dt.timezone.utc)
        print(f"[CGM-REFRESH] ═══ PREDICTION REQUEST ═══")
        print(f"[CGM-REFRESH]   CURRENT TIME: {now.isoformat()}")
        service = _get_service()
        readings = service.provider.get_readings()
        print(f"[CGM-REFRESH]   Readings available: {len(readings)}")
        if readings:
            print(f"[CGM-REFRESH]   Window: {readings[-1].timestamp.isoformat()} → "
                  f"{readings[0].timestamp.isoformat()}")
        result = service.predict_from_history()
        print(f"[CGM-REFRESH] ✅ Prediction: 30min={result['prediction_30_min']:.1f}, "
              f"60min={result['prediction_60_min']:.1f}, "
              f"total_iob={result.get('total_iob', 'N/A')} U")
        print(f"[CGM-REFRESH]   Full response dict: {result}")
        response_model = CGMPredictionResponse(**result)
        print(f"[CGM-REFRESH]   Serialized response: "
              f"prediction_30_min={response_model.prediction_30_min}, "
              f"prediction_60_min={response_model.prediction_60_min}, "
              f"total_iob={response_model.total_iob}, "
              f"readings_used={response_model.readings_used}")
        print(f"[CGM-REFRESH] ═══════════════════════════")
        return response_model
    except ValueError as exc:
        print(f"[CGM-API] ❌ Insufficient readings: {exc}")
        raise HTTPException(
            status_code=400,
            detail=str(exc),
        )
    except Exception as exc:
        print(f"[CGM-API] ❌ Prediction failed: {exc}")
        raise HTTPException(
            status_code=500,
            detail=f"CGM prediction failed: {exc}",
        )


# ── Connect / Disconnect ────────────────────────────────────────────────

@router.post(
    "/connect",
    response_model=CGMProviderStatus,
    summary="Connect a CGM provider",
)
def connect_cgm():
    """Mark the current CGM provider as connected and persist the state."""
    import datetime as _dt
    _t0 = _dt.datetime.now(_dt.timezone.utc)
    print(f"[CGM-DEBUG] ═══ /api/v1/cgm/connect REACHED at {_t0.isoformat()} ═══")
    try:
        print(f"[CGM-DEBUG]   Step 1: Resolving CGM service…")
        service = _get_service()
        print(f"[CGM-DEBUG]   Step 2: Provider selected: {service.provider.name} "
              f"(available={service.provider.is_available})")
        now = datetime.now(timezone.utc).isoformat()
        from ..repositories.base import CGMConnectionRecord
        print(f"[CGM-DEBUG]   Step 3: Persisting connection state…")
        service.persist_connection(
            CGMConnectionRecord(
                provider_name=service.provider.name,
                status="connected",
                connected_at=now,
                last_sync_at=now,
            )
        )
        print(f"[CGM-DEBUG]   Step 4: Connection state persisted ✓")
        print(f"[CGM-DEBUG]   Step 5: Fetching status for response…")
        status = service.get_status()
        print(f"[CGM-DEBUG]   Step 6: Status fetched ✓ — is_connected={status.get('is_connected')}")
        _t1 = _dt.datetime.now(_dt.timezone.utc)
        print(f"[CGM-DEBUG] ═══ /connect completed in {(_t1 - _t0).total_seconds():.2f}s ═══")
        return CGMProviderStatus(**status)
    except Exception as exc:
        print(f"[CGM-DEBUG] ❌ /connect FAILED: {exc}")
        raise HTTPException(
            status_code=500,
            detail=f"Failed to connect CGM: {exc}",
        )


@router.post(
    "/disconnect",
    response_model=CGMProviderStatus,
    summary="Disconnect a CGM provider",
)
def disconnect_cgm():
    """Remove persisted connection state for the current provider."""
    try:
        service = _get_service()
        service.remove_connection(service.provider.name)
        status = service.get_status()
        return CGMProviderStatus(**status)
    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to disconnect CGM: {exc}",
        )
