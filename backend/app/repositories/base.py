"""Repository abstraction for the nutrition data layer.

``NutritionRepository`` is the single seam between business/API logic and the
underlying nutrition storage. Recognition code and API endpoints depend on
this interface — never on a concrete storage implementation — so the storage
mechanism can be replaced later (e.g. PostgreSQL) without changing the
recognition pipeline.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional

from ..models.food import Food, FoodNutrition


@dataclass
class FoodMatch:
    """Metadata about how a free-text name was matched to a canonical food.

    ``tier`` records how the match was found so callers can apply reliability
    policies (e.g. reject low-confidence fuzzy matches):

    - ``exact``     the normalized name matched an alias exactly
    - ``substring`` the name was found as a substring of an alias
    - ``fuzzy``     a close-match algorithm resolved it (``score`` applies)
    - ``alias``     the repository could not classify the match (default)
    """

    food_id: str
    tier: str
    score: Optional[float] = None


class NutritionRepository(ABC):
    """Data-access interface for foods and their nutrition values.

    Errors raised are ``FoodNotFoundError`` (``FOOD_NOT_FOUND``) and
    ``NutritionDataNotFoundError`` (``NUTRITION_DATA_NOT_FOUND``) from
    ``backend.app.models.errors``.
    """

    @abstractmethod
    def get_food(self, food_id: str) -> Food:
        """Return the canonical food entry for ``food_id``.

        Raises ``FoodNotFoundError`` when no food matches.
        """

    @abstractmethod
    def get_nutrition(self, food_id: str) -> FoodNutrition:
        """Return per-100g nutrition values for ``food_id``.

        Raises ``FoodNotFoundError`` when the food is unknown, or
        ``NutritionDataNotFoundError`` when the food has no nutrition values.
        """

    def find_food_id(self, name: str) -> Optional[str]:
        """Resolve a free-text food name/alias to a stable ``food_id``.

        Returns ``None`` when nothing matches. This supports the Food
        Normalization stage (multiple names mapping to one stable food id).
        Repositories that keep aliases override it; the default returns None.
        """
        return None

    def find_food_match(self, name: str) -> Optional[FoodMatch]:
        """Resolve ``name`` to match metadata (id + tier + score).

        The default classifies any ``find_food_id`` hit as a reliable ``alias``
        match; repositories that can classify the match type override this.
        """
        food_id = self.find_food_id(name)
        if food_id is None:
            return None
        return FoodMatch(food_id=food_id, tier="alias", score=1.0)