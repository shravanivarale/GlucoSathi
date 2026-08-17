"""Domain entities for the Food Nutrition data layer.

These models represent the LOGICAL database design and the normalization
contract that a future dataset importer must produce. They are deliberately
independent of any physical database technology, of the actual nutrition
dataset (INDB / IFCT / another approved source), and of the recognition layer
(Gemini / the team's ML model).

Nutrition values use a canonical PER 100 GRAMS basis wherever the source
dataset supports it. The recognition model must never be treated as
authoritative for these values.

These are SCHEMA CONTRACTS only: no production food or nutrition records are
populated yet. The actual dataset is obtained and integrated in a later stage,
and the then-written importer maps its columns onto these normalized records.
"""

from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class Food(BaseModel):
    """A canonical, recognized food item (schema only, not a stored record).

    ``food_id`` is the stable identifier; ``food_name`` must not be used as a
    primary key because names may change or have aliases.
    """

    model_config = ConfigDict(extra="forbid")

    food_id: str
    food_name: str
    category: str
    nutrition_source: str
    # Populated only if the chosen dataset provides a reference serving size;
    # left unset until confirmed during dataset integration.
    reference_serving_g: Optional[float] = Field(default=None, gt=0)


class FoodNutrition(BaseModel):
    """Nutrition values for a food on a per-100g basis (schema only).

    Values come from the nutrition dataset/database (e.g. INDB) — never from
    the recognition model.
    """

    model_config = ConfigDict(extra="forbid")

    food_id: str
    nutrition_source: str
    carbs_g_per_100g: float = Field(ge=0)
    protein_g_per_100g: float = Field(ge=0)
    fat_g_per_100g: float = Field(ge=0)
    fiber_g_per_100g: float = Field(ge=0)
    calories_per_100g: float = Field(ge=0)


class ServingNutrition(BaseModel):
    """Nutrition values computed for a specific serving size.

    This is the result of scaling ``FoodNutrition`` (per-100g basis) by an
    estimated serving size. It is the bridge between the data layer and the
    API response model ``backend.app.schemas.meal.NutritionInfo``; field names
    intentionally mirror the API contract.
    """

    model_config = ConfigDict(extra="forbid")

    food_id: str
    serving_size_g: float = Field(gt=0)
    carbs_g: float = Field(ge=0)
    protein_g: float = Field(ge=0)
    fat_g: float = Field(ge=0)
    fiber_g: float = Field(ge=0)
    calories: float = Field(ge=0)
    nutrition_source: str