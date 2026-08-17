"""Repository layer for the nutrition data.

Business/API logic depends on ``NutritionRepository`` (see ``base.py``);
concrete storage implementations (currently in-memory, later the selected
physical database) implement that interface.

No production data is seeded: the actual dataset (e.g. INDB/IFCT) is obtained
and integrated in a later stage. Synthetic records exist only inside tests.
"""

from .base import NutritionRepository
from .in_memory import InMemoryNutritionRepository

__all__ = [
    "NutritionRepository",
    "InMemoryNutritionRepository",
]