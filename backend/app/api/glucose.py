from __future__ import annotations

import pandas as pd
from fastapi import APIRouter, HTTPException

from ..schemas.glucose import (
    GlucosePredictionRequest,
    GlucosePredictionResponse,
)
from ..services.glucose_predictor import get_glucose_predictor
from ..services.glucose_preprocessor import preprocess_history


router = APIRouter(
    prefix="/api/v1/glucose",
    tags=["glucose"],
)


@router.post(
    "/predict",
    response_model=GlucosePredictionResponse,
)
def predict_glucose(
    request: GlucosePredictionRequest,
):
    try:
        predictor = get_glucose_predictor()
        result = predictor.predict(request.features)

        return GlucosePredictionResponse(**result)

    except ValueError as exc:
        raise HTTPException(
            status_code=400,
            detail=str(exc),
        )

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Prediction failed: {exc}",
        )


@router.post(
    "/predict-raw",
    response_model=GlucosePredictionResponse,
)
def predict_raw_glucose(
    readings: list[dict],
):
    try:
        if len(readings) < 24:
            raise ValueError(
                "At least 24 glucose readings are required."
            )

        df = pd.DataFrame(readings)

        predictor = get_glucose_predictor()

        scaled_features = preprocess_history(
            df,
            predictor.feature_mean,
            predictor.feature_scale,
        )

        result = predictor.predict_scaled(
            scaled_features
        )

        return GlucosePredictionResponse(**result)

    except ValueError as exc:
        raise HTTPException(
            status_code=400,
            detail=str(exc),
        )

    except Exception as exc:
        raise HTTPException(
            status_code=500,
            detail=f"Raw prediction failed: {exc}",
        )

