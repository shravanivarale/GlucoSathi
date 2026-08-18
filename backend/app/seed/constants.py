"""Dataset-level constants for the INDB import.

``INDB`` is the canonical ``nutrition_source`` id used throughout the
application (see ``docs/api-contract.md``: ``nutrition_source`` is the
nutrition-database id, e.g. ``INDB``). The workbook's own ``primarysource``
column (``asc_manual`` / ``bfp_manual`` / ``open_source_recipes``) is
preserved as dataset provenance and is NOT used as ``nutrition_source``.
"""

from pathlib import Path

# Canonical nutrition-database id reported by the app contract.
NUTRITION_SOURCE = "INDB"

# Default location of the dataset workbook relative to the repo root.
DEFAULT_XLSX_PATH = Path(__file__).resolve().parents[3] / "data" / "Anuvaad_INDB_2024.11.xlsx"

# Column name mapping INDB -> normalized application schema.
COLUMN_MAP = {
    "food_code": "food_id",
    "food_name": "food_name",
    "primarysource": "dataset_source",
    # Per-100g nutrition (canonical basis).
    "energy_kcal": "calories_per_100g",
    "carb_g": "carbs_g_per_100g",
    "protein_g": "protein_g_per_100g",
    "fat_g": "fat_g_per_100g",
    "fibre_g": "fiber_g_per_100g",
    # Reference serving (named portion, not a gram weight).
    "servings_unit": "serving_name",
    "unit_serving_energy_kcal": "serving_calories",
    "unit_serving_carb_g": "serving_carbs_g",
    "unit_serving_protein_g": "serving_protein_g",
    "unit_serving_fat_g": "serving_fat_g",
    "unit_serving_fibre_g": "serving_fiber_g",
}

# Required per-100g nutrition columns the import must cover.
REQUIRED_NUTRITION_COLUMNS = [
    "energy_kcal",
    "carb_g",
    "protein_g",
    "fat_g",
    "fibre_g",
]

# Serving columns required to record a reference serving.
SERVING_NAME_COLUMN = "servings_unit"
REQUIRED_SERVING_COLUMNS = [
    "unit_serving_energy_kcal",
    "unit_serving_carb_g",
    "unit_serving_protein_g",
    "unit_serving_fat_g",
    "unit_serving_fibre_g",
]
