"""Physical-database record types for the INDB data layer.

These describe how dataset rows are stored in the seeded database. They are
deliberately separate from the finalized logical contract in
``app/models/food.py`` (``Food`` / ``FoodNutrition`` / ``ServingNutrition``);
``ServingRecord`` represents INDB's own per-serving nutrition (a named
portion, e.g. one ``dosa`` or one ``bowl``), which the logical contract does
not model.
"""

from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class ServingRecord(BaseModel):
    """Nutrition values for INDB's named reference serving.

    ``serving_name`` is the dataset's ``servings_unit`` (e.g. ``bowl``,
    ``dosa``, ``parantha``). INDB does not provide a gram weight for the
    serving, so ``serving_size_g`` is left ``None`` unless one is supplied.
    """

    model_config = ConfigDict(extra="forbid")

    food_id: str
    serving_name: str
    serving_size_g: Optional[float] = Field(default=None, gt=0)
    carbs_g: float = Field(ge=0)
    protein_g: float = Field(ge=0)
    fat_g: float = Field(ge=0)
    fiber_g: float = Field(ge=0)
    calories: float = Field(ge=0)