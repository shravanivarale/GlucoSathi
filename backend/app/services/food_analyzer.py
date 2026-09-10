"""Food analysis pipeline: recognition -> INDB nutrition lookup.

Combines a ``FoodRecognizer`` (Gemini Vision) with a ``NutritionRepository``
(SQLite seeded from INDB):

    Image -> Gemini Vision -> food items -> INDB search per item -> meal result

The recognizer names every distinct food in the image; every nutrition value
comes from the repository (INDB). If no reliable INDB match exists for an
item no value is invented and that item's ``matched`` is ``False``.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict, Optional

from ..models.errors import FoodRecognitionError
from ..repositories.base import NutritionRepository
from .gemini_service import FoodRecognizer

# Fuzzy-only matches (no exact/substring alias) are accepted only when the
# name is close enough to the alias; below this a match is likely coincidental
# (e.g. "Rajma Chawal" -> "amla achaar" at 0.696) and would fabricate values.
MIN_FUZZY_SCORE = 0.75

# Nutrition keys used in per-100g payloads and aggregation.
_NUTRITION_KEYS = ("carb_g", "protein_g", "fat_g", "fibre_g", "energy_kcal")


@dataclass
class FoodAnalysisResult:
    """Result of running the full recognize-and-match pipeline for ONE food."""

    recognized_food: str
    matched: bool = False
    food_id: Optional[str] = None
    food_name: Optional[str] = None
    nutrition: Optional[dict] = None
    message: Optional[str] = None


@dataclass
class MealAnalysisResult:
    """Aggregated result for an entire meal (one or more foods)."""

    foods: list[FoodAnalysisResult] = field(default_factory=list)
    total_nutrition: Optional[dict] = None


def to_nutrition_payload(food_id: str, repository: NutritionRepository) -> dict:
    """Map an INDB per-100g nutrition record to the API payload.

    Field names mirror the INDB workbook columns; ``basis`` records that all
    values are per 100 grams of the food as served (INDB's canonical basis).
    """
    nutrition = repository.get_nutrition(food_id)
    return {
        "carb_g": nutrition.carbs_g_per_100g,
        "protein_g": nutrition.protein_g_per_100g,
        "fat_g": nutrition.fat_g_per_100g,
        "fibre_g": nutrition.fiber_g_per_100g,
        "energy_kcal": nutrition.calories_per_100g,
        "basis": "per_100g",
        "nutrition_source": nutrition.nutrition_source,
    }


def aggregate_nutrition(foods: list[FoodAnalysisResult]) -> Optional[dict]:
    """Sum per-100g nutrition across all matched foods in the meal.

    Returns ``None`` when no food was matched (no nutrition to aggregate).
    """
    totals: Dict[str, float] = {k: 0.0 for k in _NUTRITION_KEYS}
    matched_count = 0
    for f in foods:
        if f.matched and f.nutrition:
            for k in _NUTRITION_KEYS:
                totals[k] += f.nutrition.get(k, 0.0)
            matched_count += 1
    if matched_count == 0:
        return None
    return totals


class FoodAnalyzer:
    """Pipeline that turns an image into recognized foods + INDB nutrition."""

    def __init__(
        self,
        recognizer: FoodRecognizer,
        repository: NutritionRepository,
    ) -> None:
        self._recognizer = recognizer
        self._repository = repository

    def recognize(self, image_bytes: bytes, mime_type: str) -> MealAnalysisResult:
        """Recognize the food names only (no nutrition lookup)."""
        recognized_items = self._recognizer.recognize(image_bytes, mime_type)
        return MealAnalysisResult(
            foods=[
                FoodAnalysisResult(recognized_food=rf.food_name)
                for rf in recognized_items
            ]
        )

    def analyze(self, image_bytes: bytes, mime_type: str) -> MealAnalysisResult:
        """Run the complete workflow and return matched nutrition (if any)."""
        recognized_items = self._recognizer.recognize(image_bytes, mime_type)
        results = [self.lookup(rf.food_name) for rf in recognized_items]
        return MealAnalysisResult(
            foods=results,
            total_nutrition=aggregate_nutrition(results),
        )

    def lookup(self, recognized_food: str) -> FoodAnalysisResult:
        """Match a recognized food name against INDB and return nutrition."""
        match = self._repository.find_food_match(recognized_food)
        if match is None:
            return FoodAnalysisResult(
                recognized_food=recognized_food,
                matched=False,
                message="Food not found in nutrition database",
            )
        if match.tier == "fuzzy" and (
            match.score is None or match.score < MIN_FUZZY_SCORE
        ):
            return FoodAnalysisResult(
                recognized_food=recognized_food,
                matched=False,
                message="Food not found in nutrition database",
            )

        food = self._repository.get_food(match.food_id)
        return FoodAnalysisResult(
            recognized_food=recognized_food,
            matched=True,
            food_id=food.food_id,
            food_name=food.food_name,
            nutrition=to_nutrition_payload(food.food_id, self._repository),
        )
