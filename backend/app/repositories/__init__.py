"""Repository layer for the nutrition, CGM, and insulin data.

Business/API logic depends on ``NutritionRepository``, ``CGMRepository``,
and ``InsulinLogRepository`` (see ``base.py``); concrete storage
implementations (currently SQLite) implement those interfaces.
"""

from .base import (
    CGMConnectionRecord,
    CGMPredictionRecord,
    CGMReadingRecord,
    CGMRepository,
    INSULIN_TYPE_MAP,
    INSULIN_TYPE_NPH,
    INSULIN_TYPE_RAPID,
    INSULIN_TYPE_REGULAR,
    InsulinLogRecord,
    InsulinLogRepository,
    NutritionRepository,
)
from .in_memory import InMemoryNutritionRepository

__all__ = [
    "CGMConnectionRecord",
    "CGMPredictionRecord",
    "CGMReadingRecord",
    "CGMRepository",
    "INSULIN_TYPE_MAP",
    "INSULIN_TYPE_NPH",
    "INSULIN_TYPE_RAPID",
    "INSULIN_TYPE_REGULAR",
    "InsulinLogRecord",
    "InsulinLogRepository",
    "NutritionRepository",
    "InMemoryNutritionRepository",
]