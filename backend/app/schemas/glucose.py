from pydantic import BaseModel, Field


class GlucosePredictionRequest(BaseModel):
    features: list[list[float]] = Field(
        ...,
        description="24 time steps × 12 glucose model features",
    )


class GlucosePredictionResponse(BaseModel):
    prediction_30_min: float
    prediction_60_min: float
    unit: str = "mg/dL"
