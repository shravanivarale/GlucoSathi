"""Response schemas for the Food Recognition API.

This module defines the Pydantic request/response contracts for
``POST /api/v1/food/analyze``. The written contract is documented in
``docs/api-contract.md``; failure codes are documented in
``docs/failure-cases.md``.
"""

from typing import Literal, Optional

from pydantic import BaseModel, ConfigDict, Field


class NutritionInfo(BaseModel):
    """Nutrition values for the estimated serving size.

    Sourced from the nutrition database (e.g. INDB) — never from the
    recognition model. Values correspond to ``MealResult.estimated_serving_size_g``.
    """

    model_config = ConfigDict(extra="forbid")

    carbs_g: float = Field(ge=0)
    protein_g: float = Field(ge=0)
    fat_g: float = Field(ge=0)
    fiber_g: float = Field(ge=0)
    calories: float = Field(ge=0)
    nutrition_source: str


class MealResult(BaseModel):
    """Final analysis result for a single meal.

    Clearly separates three layers:

    1. Recognition: ``food_id``, ``food_name``, ``recognition_confidence``
    2. Portion estimate: ``estimated_serving_size_g``
    3. Nutrition: ``nutrition`` (from the nutrition database)
    """

    model_config = ConfigDict(extra="forbid")

    meal_id: str
    food_id: str
    food_name: str
    recognition_confidence: float = Field(ge=0.0, le=1.0)
    estimated_serving_size_g: float = Field(gt=0)
    nutrition: NutritionInfo


class ApiError(BaseModel):
    """Machine-readable error detail returned on failure.

    ``code`` maps to the codes documented in ``docs/failure-cases.md``.
    """

    model_config = ConfigDict(extra="forbid")

    code: str
    message: str


class FoodAnalyzeSuccess(BaseModel):
    """Success envelope for ``POST /api/v1/food/analyze``."""

    model_config = ConfigDict(extra="forbid")

    success: Literal[True] = True
    data: MealResult
    error: Optional[ApiError] = None


class FoodAnalyzeError(BaseModel):
    """Failure envelope for ``POST /api/v1/food/analyze``."""

    model_config = ConfigDict(extra="forbid")

    success: Literal[False] = False
    data: None = None
    error: ApiError