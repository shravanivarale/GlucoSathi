"""INDB dataset import (ETL) and seed tooling.

Provides an idempotent, repeatable pipeline from the INDB workbook onto the
application's normalized schema (``app/models/food.py``) and into the SQLite
nutrition database (``app/database/sqlite.py``):

- ``inspect``   read-only workbook analysis (coverage, duplicates, nulls)
- ``importer``  INDB -> ``Food`` / ``FoodNutrition`` / ``ServingRecord``
- ``aliases``   food-name alias derivation for Food Normalization
- ``category``  keyword category classification for display grouping
- ``seed``      CLI: ``python -m app.seed.seed``
"""