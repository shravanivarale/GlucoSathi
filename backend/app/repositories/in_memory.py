"""In-memory implementation of the nutrition repository.

The repository ships EMPTY: the actual nutrition dataset (e.g. INDB/IFCT) is
not available yet, so no production food or nutrition records are seeded.
Tests inject their own synthetic fixtures (``backend/tests/synthetic_data.py``).

This is throwaway storage so the data layer can run and be tested without
locking us into a production database. The physical database technology will
be decided separately and wired behind ``NutritionRepository``.
"""

from typing import Optional

from ..models.errors import (
    FoodNotFoundError,
    NutritionDataNotFoundError,
)
from ..models.food import Food, FoodNutrition
from .base import NutritionRepository


class InMemoryNutritionRepository(NutritionRepository):
    """Keeps foods and per-100g nutrition in process memory.

    Starts empty. Populate via constructor arguments (e.g. from synthetic
    test fixtures) or, later, by wiring the dataset-derived records through a
    database-backed repository.
    """

    def __init__(
        self,
        foods: Optional[list[Food]] = None,
        nutrition: Optional[list[FoodNutrition]] = None,
        aliases: Optional[dict[str, str]] = None,
    ) -> None:
        self._foods: dict[str, Food] = {
            food.food_id: food for food in (foods or [])
        }
        self._nutrition: dict[str, FoodNutrition] = {
            entry.food_id: entry for entry in (nutrition or [])
        }
        self._aliases: dict[str, str] = dict(aliases or {})

    def get_food(self, food_id: str) -> Food:
        food = self._foods.get(food_id)
        if food is None:
            raise FoodNotFoundError(
                f"Food {food_id!r} not found in the nutrition database"
            )
        return food

    def get_nutrition(self, food_id: str) -> FoodNutrition:
        # Fail with FOOD_NOT_FOUND when the food itself is unknown.
        self.get_food(food_id)
        nutrition = self._nutrition.get(food_id)
        if nutrition is None:
            raise NutritionDataNotFoundError(
                f"Nutrition data unavailable for food {food_id!r}"
            )
        return nutrition

    def find_food_id(self, name: str) -> Optional[str]:
        return self._aliases.get(name.strip().lower())