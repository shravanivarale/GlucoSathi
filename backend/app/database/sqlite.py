"""SQLite-backed implementation of ``NutritionRepository``.

This is the physical database chosen for the seeded INDB dataset. It
implements the SAME ``NutritionRepository`` interface used by the
``InMemoryNutritionRepository`` (see ``app/repositories/base.py``), so the
storage technology can be swapped (e.g. PostgreSQL) without touching business
or API logic. Logical records follow ``app/models/food.py``; the reference
serving is stored as ``ServingRecord`` (``app/database/records.py``).

Tables
------
``foods``          canonical food records (``Food``)
``food_nutrition``  per-100g values (``FoodNutrition``)
``food_alias``      alias -> ``food_id`` (Food Normalization)
``food_servings``   INDB named reference serving (``ServingRecord``)
"""

from pathlib import Path
from typing import Optional

import sqlite3

from ..models.errors import (
    FoodNotFoundError,
    NutritionDataNotFoundError,
)
from ..models.food import Food, FoodNutrition
from ..repositories.base import NutritionRepository
from .records import ServingRecord

DEFAULT_DB_PATH = Path(__file__).resolve().parents[2] / "data" / "glucosaathi.db"

INIT_SCHEMA = """
CREATE TABLE IF NOT EXISTS foods (
    food_id             TEXT PRIMARY KEY,
    food_name           TEXT NOT NULL,
    category            TEXT NOT NULL,
    nutrition_source    TEXT NOT NULL,
    dataset_source      TEXT,
    reference_serving_g REAL
);

CREATE TABLE IF NOT EXISTS food_nutrition (
    food_id            TEXT PRIMARY KEY REFERENCES foods(food_id),
    nutrition_source   TEXT NOT NULL,
    carbs_g_per_100g   REAL NOT NULL CHECK (carbs_g_per_100g >= 0),
    protein_g_per_100g REAL NOT NULL CHECK (protein_g_per_100g >= 0),
    fat_g_per_100g     REAL NOT NULL CHECK (fat_g_per_100g >= 0),
    fiber_g_per_100g   REAL NOT NULL CHECK (fiber_g_per_100g >= 0),
    calories_per_100g  REAL NOT NULL CHECK (calories_per_100g >= 0)
);

CREATE TABLE IF NOT EXISTS food_alias (
    alias   TEXT PRIMARY KEY,
    food_id TEXT NOT NULL REFERENCES foods(food_id)
);
CREATE INDEX IF NOT EXISTS idx_food_alias_food_id ON food_alias(food_id);

CREATE TABLE IF NOT EXISTS food_servings (
    food_id         TEXT PRIMARY KEY REFERENCES foods(food_id),
    serving_name    TEXT NOT NULL,
    serving_size_g  REAL,
    carbs_g         REAL NOT NULL CHECK (carbs_g >= 0),
    protein_g       REAL NOT NULL CHECK (protein_g >= 0),
    fat_g           REAL NOT NULL CHECK (fat_g >= 0),
    fiber_g         REAL NOT NULL CHECK (fiber_g >= 0),
    calories        REAL NOT NULL CHECK (calories >= 0)
);
"""


def connect(db_path: str | Path | None = None) -> sqlite3.Connection:
    """Open (and if needed create) the SQLite database file."""
    path = Path(db_path) if db_path else DEFAULT_DB_PATH
    path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(path))
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def init_schema(conn: sqlite3.Connection) -> None:
    """Create tables/indexes if they do not exist."""
    conn.executescript(INIT_SCHEMA)


def normalize_label(name: str) -> str:
    """Normalize a free-text label for alias lookup."""
    return " ".join(name.strip().lower().split())


def _escape_like(value: str) -> str:
    """Escape SQL LIKE wildcards so the label is matched literally."""
    return value.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")


def _common_prefix_len(a: str, b: str) -> int:
    i = 0
    for x, y in zip(a, b):
        if x != y:
            break
        i += 1
    return i


def _fuzzy_prefix_boost(query: str, alias: str) -> float:
    """Reward candidates whose leading characters / first word match the query.

    Without this boost pure difflib ratio can route a typo to the wrong food
    ("alu paratha" -> "dal paratha" 0.909 beats "aloo paratha" 0.870); the
    shared-prefix term keeps the intended entry on top.
    """
    whole = _common_prefix_len(query, alias) / max(len(query), len(alias), 1)
    q_first = query.split()[0] if query.split() else ""
    a_first = alias.split()[0] if alias.split() else ""
    first = (
        _common_prefix_len(q_first, a_first) / max(len(q_first), len(a_first), 1)
        if q_first and a_first
        else 0.0
    )
    return 0.15 * whole + 0.25 * first


class SQLiteNutritionRepository(NutritionRepository):
    """Persistent repository backed by a SQLite database file."""

    def __init__(self, db_path: str | Path | None = None) -> None:
        self.db_path = Path(db_path) if db_path else DEFAULT_DB_PATH

    def _connect(self) -> sqlite3.Connection:
        conn = connect(self.db_path)
        init_schema(conn)
        return conn

    # --- NutritionRepository interface -------------------------------------

    def get_food(self, food_id: str) -> Food:
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM foods WHERE food_id = ?", (food_id,)
            ).fetchone()
        if row is None:
            raise FoodNotFoundError(
                f"Food {food_id!r} not found in the nutrition database"
            )
        return Food(
            food_id=row["food_id"],
            food_name=row["food_name"],
            category=row["category"],
            nutrition_source=row["nutrition_source"],
            reference_serving_g=row["reference_serving_g"],
        )

    def get_nutrition(self, food_id: str) -> FoodNutrition:
        # Fail with FOOD_NOT_FOUND when the food itself is unknown.
        self.get_food(food_id)
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM food_nutrition WHERE food_id = ?", (food_id,)
            ).fetchone()
        if row is None:
            raise NutritionDataNotFoundError(
                f"Nutrition data unavailable for food {food_id!r}"
            )
        return FoodNutrition(
            food_id=row["food_id"],
            nutrition_source=row["nutrition_source"],
            carbs_g_per_100g=row["carbs_g_per_100g"],
            protein_g_per_100g=row["protein_g_per_100g"],
            fat_g_per_100g=row["fat_g_per_100g"],
            fiber_g_per_100g=row["fiber_g_per_100g"],
            calories_per_100g=row["calories_per_100g"],
        )

    def find_food_id(self, name: str) -> Optional[str]:
        label = normalize_label(name)
        if not label:
            return None

        # 1. Exact alias match (fast path).
        with self._connect() as conn:
            row = conn.execute(
                "SELECT food_id FROM food_alias WHERE alias = ?",
                (label,),
            ).fetchone()
            if row:
                return row["food_id"]

            # 2. Substring match (SQL LIKE), preferring the shortest alias so a
            #    partial query resolves to the most generic matching food.
            if len(label) >= 3:
                row = conn.execute(
                    "SELECT food_id, LENGTH(alias) AS ln"
                    " FROM food_alias"
                    " WHERE alias LIKE ? ESCAPE '\\'"
                    " ORDER BY ln ASC LIMIT 1",
                    (f"%{_escape_like(label)}%",),
                ).fetchone()
                if row:
                    return row["food_id"]

            # 3. Fuzzy close-match (typos such as "alu paratha"). Rank
            #    candidates by difflib ratio plus a prefix-similarity boost so
            #    the intended food wins among close-scoring neighbours: pure
            #    ratio scores "alu paratha" closer to "dal paratha" (0.909)
            #    than to "aloo paratha" (0.870) even though the intended one
            #    shares a spelling prefix.
            aliases = [
                dict(r) for r in conn.execute(
                    "SELECT alias, food_id FROM food_alias ORDER BY alias"
                ).fetchall()
            ]
        from difflib import SequenceMatcher

        best: Optional[tuple[float, str]] = None  # (score, alias)
        for a in aliases:
            ratio = SequenceMatcher(
                None, label, a["alias"], autojunk=False
            ).ratio()
            if ratio < 0.6:
                continue
            score = ratio + _fuzzy_prefix_boost(label, a["alias"])
            if (
                best is None
                or score > best[0]
                or (score == best[0] and a["alias"] < best[1])
            ):
                best = (score, a["alias"])
        if best:
            for a in aliases:
                if a["alias"] == best[1]:
                    return a["food_id"]
        return None

    # --- Concrete additions (not part of the abstract interface) -----------

    def find_food(self, name: str) -> Optional[Food]:
        """Resolve a name/alias to a canonical food, or ``None``."""
        food_id = self.find_food_id(name)
        if food_id is None:
            return None
        return self.get_food(food_id)

    def get_serving(self, food_id: str) -> Optional[ServingRecord]:
        self.get_food(food_id)
        with self._connect() as conn:
            row = conn.execute(
                "SELECT * FROM food_servings WHERE food_id = ?", (food_id,)
            ).fetchone()
        if row is None:
            return None
        return ServingRecord(
            food_id=row["food_id"],
            serving_name=row["serving_name"],
            serving_size_g=row["serving_size_g"],
            carbs_g=row["carbs_g"],
            protein_g=row["protein_g"],
            fat_g=row["fat_g"],
            fiber_g=row["fiber_g"],
            calories=row["calories"],
        )

    def counts(self) -> dict[str, int]:
        """Return the number of rows in each table (for seeding verification)."""
        with self._connect() as conn:
            foods = conn.execute("SELECT COUNT(*) AS n FROM foods").fetchone()["n"]
            nutrition = conn.execute(
                "SELECT COUNT(*) AS n FROM food_nutrition"
            ).fetchone()["n"]
            aliases = conn.execute(
                "SELECT COUNT(*) AS n FROM food_alias"
            ).fetchone()["n"]
            servings = conn.execute(
                "SELECT COUNT(*) AS n FROM food_servings"
            ).fetchone()["n"]
        return {
            "foods": foods,
            "nutrition": nutrition,
            "aliases": aliases,
            "servings": servings,
        }