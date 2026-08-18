"""FastAPI dependency wiring for the food recognition endpoints.

These dependencies let tests replace components easily via
``app.dependency_overrides`` (all Gemini calls are mocked in automated tests).
"""

from __future__ import annotations

from typing import Optional

from fastapi import Depends

from ..database.sqlite import SQLiteNutritionRepository
from ..repositories.base import NutritionRepository
from ..services.food_analyzer import FoodAnalyzer
from ..services.gemini_service import FoodRecognizer, GeminiVisionRecognizer


def get_nutrition_repository() -> NutritionRepository:
    """Return the INDB-backed SQLite repository (production default)."""
    return SQLiteNutritionRepository()


_shared_recognizer: Optional[GeminiVisionRecognizer] = None


def get_food_recognizer() -> FoodRecognizer:
    """Return the shared Gemini Vision recognizer (production default).

    A single recognizer — and its single underlying Gemini client — is reused
    across all requests, so the connection pool is not recreated per request.
    It is closed once at application shutdown via [close_food_recognizer].
    """
    global _shared_recognizer
    if _shared_recognizer is None:
        _shared_recognizer = GeminiVisionRecognizer()
    return _shared_recognizer


def close_food_recognizer() -> None:
    """Close the shared Gemini client at application shutdown (idempotent)."""
    global _shared_recognizer
    if _shared_recognizer is not None:
        _shared_recognizer.close()
        _shared_recognizer = None


def get_food_analyzer(
    recognizer: FoodRecognizer = Depends(get_food_recognizer),
    repository: NutritionRepository = Depends(get_nutrition_repository),
) -> FoodAnalyzer:
    """Assemble the analysis pipeline from its dependencies."""
    return FoodAnalyzer(recognizer=recognizer, repository=repository)