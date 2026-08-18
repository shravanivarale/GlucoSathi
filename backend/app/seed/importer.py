"""Map INDB workbook rows onto the application's normalized schema.

INDB field mapping (see ``constants.COLUMN_MAP``):

- ``food_code``       -> ``Food.food_id`` (stable identifier)
- ``food_name``       -> ``Food.food_name`` (canonical name)
- ``primarysource``   -> stored as dataset provenance ``dataset_source``
                        (``Food.nutrition_source`` is always ``INDB``)
- ``energy_kcal``     -> ``FoodNutrition.calories_per_100g``
- ``carb_g``          -> ``FoodNutrition.carbs_g_per_100g``
- ``protein_g``       -> ``FoodNutrition.protein_g_per_100g``
- ``fat_g``           -> ``FoodNutrition.fat_g_per_100g``
- ``fibre_g``         -> ``FoodNutrition.fiber_g_per_100g``
- ``servings_unit`` + ``unit_serving_*`` -> ``ServingRecord`` (named portion)

``reference_serving_g`` stays unset: INDB describes its serving by name/nutrient
values, not by a gram weight.
"""

from pathlib import Path
from typing import Any

import pandas as pd

from app.database.records import ServingRecord
from app.models.food import Food, FoodNutrition

from .aliases import build_alias_map
from .category import classify
from .constants import (
    NUTRITION_SOURCE,
    REQUIRED_NUTRITION_COLUMNS,
    REQUIRED_SERVING_COLUMNS,
    SERVING_NAME_COLUMN,
)


class ImportError_(Exception):
    """Raised when the workbook cannot be mapped onto the app schema."""


class ImportedDataset:
    """Normalized dataset ready to be seeded (schema records + alias map).

    ``dataset_sources`` maps each ``food_id`` to its INDB ``primarysource``
    (e.g. ``asc_manual``). It is informational provenance only; the canonical
    ``nutrition_source`` for every record is ``INDB``.
    """

    def __init__(
        self,
        foods: list[Food],
        nutrition: list[FoodNutrition],
        servings: list[ServingRecord],
        aliases: dict[str, str],
        dataset_sources: dict[str, str] | None = None,
    ) -> None:
        self.foods = foods
        self.nutrition = nutrition
        self.servings = servings
        self.aliases = aliases
        self.dataset_sources = dataset_sources or {}

    def counts(self) -> dict[str, int]:
        return {
            "foods": len(self.foods),
            "nutrition": len(self.nutrition),
            "servings": len(self.servings),
            "aliases": len(self.aliases),
        }


def load_workbook(path: str | Path) -> pd.DataFrame:
    """Read the first (only) sheet of the INDB workbook."""
    df = pd.read_excel(path)
    if df.empty:
        raise ImportError_(f"Dataset {path} is empty")
    return df


def to_imported_dataset(df: pd.DataFrame) -> ImportedDataset:
    """Map a loaded INDB frame onto the application schema."""
    missing = [c for c in REQUIRED_NUTRITION_COLUMNS if c not in df.columns]
    if missing:
        raise ImportError_(
            f"Dataset missing required nutrition columns: {missing}"
        )

    foods: list[Food] = []
    nutrition: list[FoodNutrition] = []
    servings: list[ServingRecord] = []
    dataset_sources: dict[str, str] = {}
    skip_missing_nutrition = 0

    for _, row in df.iterrows():
        food_id = _to_str(row["food_code"])
        food_name = _to_str(row["food_name"])
        dataset_source = _to_str(row.get("primarysource", "")) or "unknown"

        required = {c: row.get(c) for c in REQUIRED_NUTRITION_COLUMNS}
        if any(pd.isna(v) for v in required.values()):
            skip_missing_nutrition += 1
            continue

        foods.append(
            Food(
                food_id=food_id,
                food_name=food_name,
                category=classify(food_name),
                nutrition_source=NUTRITION_SOURCE,
            )
        )
        nutrition.append(
            FoodNutrition(
                food_id=food_id,
                nutrition_source=NUTRITION_SOURCE,
                carbs_g_per_100g=_num(required["carb_g"]),
                protein_g_per_100g=_num(required["protein_g"]),
                fat_g_per_100g=_num(required["fat_g"]),
                fiber_g_per_100g=_num(required["fibre_g"]),
                calories_per_100g=_num(required["energy_kcal"]),
            )
        )

        serving = _to_serving(row, food_id)
        if serving is not None:
            servings.append(serving)

        dataset_sources[food_id] = dataset_source

    if skip_missing_nutrition:
        raise ImportError_(
            f"{skip_missing_nutrition} food(s) missing required per-100g "
            "nutrition and were not imported"
        )

    return ImportedDataset(
        foods=foods,
        nutrition=nutrition,
        servings=servings,
        aliases=build_alias_map(foods),
        dataset_sources=dataset_sources,
    )


def import_dataset(path: str | Path) -> ImportedDataset:
    """Convenience: load a workbook and map it onto the app schema."""
    return to_imported_dataset(load_workbook(path))


def _to_serving(row: Any, food_id: str) -> ServingRecord | None:
    serving_name = _to_str(row.get(SERVING_NAME_COLUMN))
    if not serving_name or pd.isna(row.get("unit_serving_energy_kcal")):
        return None
    required = {c: row.get(c) for c in REQUIRED_SERVING_COLUMNS}
    if any(pd.isna(v) for v in required.values()):
        return None
    return ServingRecord(
        food_id=food_id,
        serving_name=serving_name,
        calories=_num(required["unit_serving_energy_kcal"]),
        carbs_g=_num(required["unit_serving_carb_g"]),
        protein_g=_num(required["unit_serving_protein_g"]),
        fat_g=_num(required["unit_serving_fat_g"]),
        fiber_g=_num(required["unit_serving_fibre_g"]),
    )


def _to_str(value: Any) -> str:
    if pd.isna(value):
        return ""
    return str(value).strip()


def _num(value: Any) -> float:
    """Round to 3 decimals to remove floating-point noise from the workbook."""
    return round(float(value), 3)