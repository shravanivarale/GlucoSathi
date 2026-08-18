"""Request/response schemas for the /api/v1/foods/* endpoints.

These describe the Food Image Upload + Food Recognition MVP contract:

- ``FoodRecognizeResponse`` — POST /api/v1/foods/recognize
- ``FoodAnalyzeResponse``   — POST /api/v1/foods/analyze

Nutrition values come from INDB (per-100g basis) and are never fabricated;
when no reliable match exists ``matched`` is ``false`` and the response only
carries ``recognized_food`` and ``message``.
"""

from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class FoodRecognizeResponse(BaseModel):
    """Recognized food name returned by ``/foods/recognize``."""

    model_config = ConfigDict(extra="forbid")

    recognized_food: str = Field(description="Canonical food name from Gemini Vision")


class FoodAnalyzeResponse(BaseModel):
    """Full analysis result returned by ``/foods/analyze``.

    ``nutrition`` uses the actual INDB field names on a per-100g basis:
    ``carb_g``, ``protein_g``, ``fat_g``, ``fibre_g``, ``energy_kcal`` plus
    ``basis`` and ``nutrition_source`` metadata.
    """

    model_config = ConfigDict(extra="forbid")

    recognized_food: str
    matched: bool
    food_id: Optional[str] = None
    food_name: Optional[str] = None
    nutrition: Optional[dict] = None
    message: Optional[str] = None