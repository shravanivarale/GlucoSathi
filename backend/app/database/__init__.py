"""Database connection and session management.

The nutrition database is seeded from the INDB dataset by
``app/seed/seed.py`` and served through
``app/database/sqlite.SQLiteNutritionRepository`` behind the
``NutritionRepository`` interface.
"""

from .records import ServingRecord
from .sqlite import (
    DEFAULT_DB_PATH,
    SQLiteNutritionRepository,
    connect,
    init_schema,
)

__all__ = [
    "DEFAULT_DB_PATH",
    "SQLiteNutritionRepository",
    "ServingRecord",
    "connect",
    "init_schema",
]