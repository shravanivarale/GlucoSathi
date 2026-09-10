"""Request/response schemas for the /api/v1/foods/* endpoints.

These describe the Food Image Upload + Food Recognition MVP contract:

- ``FoodRecognizeResponse`` — POST /api/v1/foods/recognize
- ``FoodAnalyzeResponse``   — POST /api/v1/foods/analyze

A single consistent response format is used for both single-food and
multi-food images.  ``foods`` always contains a list (one element for a
single-food image, multiple elements for a meal).  ``total_nutrition``
sums per-100g values across all matched items.
"""

from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class RecognizedFoodItem(BaseModel):
    """A single food name returned by ``/foods/recognize``."""

    model_config = ConfigDict(extra="forbid")

    name: str = Field(description="Food name from Gemini Vision")


class FoodRecognizeResponse(BaseModel):
    """Recognized food names returned by ``/foods/recognize``."""

    model_config = ConfigDict(extra="forbid")

    foods: list[RecognizedFoodItem] = Field(
        description="List of distinct foods identified in the image"
    )


class SingleFoodResult(BaseModel):
    """Per-food analysis result within a meal response.

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


class FoodAnalyzeResponse(BaseModel):
    """Full analysis result returned by ``/foods/analyze``.

    ``foods`` contains one ``SingleFoodResult`` per detected food item.
    ``total_nutrition`` is the sum of per-100g values across all matched
    items (or ``None`` when nothing matched).
    """

    model_config = ConfigDict(extra="forbid")

    foods: list[SingleFoodResult]
    total_nutrition: Optional[dict] = None
