"""Database connection and session management.

The nutrition database is seeded from the INDB dataset by
``app/seed/seed.py`` and served through
``app/database/sqlite.SQLiteNutritionRepository`` behind the
``NutritionRepository`` interface.

CGM data (connections, readings, predictions) is persisted via
``app/database/sqlite.SQLiteCGMRepository`` behind the ``CGMRepository``
interface.

Insulin logs are persisted via ``app/database/sqlite.SQLiteInsulinLogRepository``
behind the ``InsulinLogRepository`` interface.
"""

from .records import ServingRecord
from .sqlite import (
    DEFAULT_DB_PATH,
    SQLiteCGMRepository,
    SQLiteInsulinLogRepository,
    SQLiteNutritionRepository,
    connect,
    init_schema,
)

__all__ = [
    "DEFAULT_DB_PATH",
    "SQLiteCGMRepository",
    "SQLiteInsulinLogRepository",
    "SQLiteNutritionRepository",
    "ServingRecord",
    "connect",
    "init_schema",
]