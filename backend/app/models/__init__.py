"""Domain entities for the Food Nutrition data layer.

These are LOGICAL database models, not tied to a physical database. They
represent foods, per-100g nutrition, and computed serving nutrition. See
``backend/app/models/food.py`` for the entities and
``backend/app/models/errors.py`` for the data-layer errors.
"""

from .errors import (
    FoodNotFoundError,
    NutritionDataError,
    NutritionDataNotFoundError,
)
from .food import Food, FoodNutrition, ServingNutrition

__all__ = [
    "Food",
    "FoodNutrition",
    "ServingNutrition",
    "NutritionDataError",
    "FoodNotFoundError",
    "NutritionDataNotFoundError",
]
