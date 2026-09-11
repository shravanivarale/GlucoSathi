"""Repository abstraction for the nutrition data layer.

``NutritionRepository`` is the single seam between business/API logic and the
underlying nutrition storage. Recognition code and API endpoints depend on
this interface — never on a concrete storage implementation — so the storage
mechanism can be replaced later (e.g. PostgreSQL) without changing the
recognition pipeline.

``CGMRepository`` is the analogous seam for CGM connection state, readings,
and predictions.
"""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Optional

from ..models.food import Food, FoodNutrition


@dataclass
class FoodMatch:
    """Metadata about how a free-text name was matched to a canonical food.

    ``tier`` records how the match was found so callers can apply reliability
    policies (e.g. reject low-confidence fuzzy matches):

    - ``exact``     the normalized name matched an alias exactly
    - ``substring`` the name was found as a substring of an alias
    - ``fuzzy``     a close-match algorithm resolved it (``score`` applies)
    - ``alias``     the repository could not classify the match (default)
    """

    food_id: str
    tier: str
    score: Optional[float] = None


class NutritionRepository(ABC):
    """Data-access interface for foods and their nutrition values.

    Errors raised are ``FoodNotFoundError`` (``FOOD_NOT_FOUND``) and
    ``NutritionDataNotFoundError`` (``NUTRITION_DATA_NOT_FOUND``) from
    ``backend.app.models.errors``.
    """

    @abstractmethod
    def get_food(self, food_id: str) -> Food:
        """Return the canonical food entry for ``food_id``.

        Raises ``FoodNotFoundError`` when no food matches.
        """

    @abstractmethod
    def get_nutrition(self, food_id: str) -> FoodNutrition:
        """Return per-100g nutrition values for ``food_id``.

        Raises ``FoodNotFoundError`` when the food is unknown, or
        ``NutritionDataNotFoundError`` when the food has no nutrition values.
        """

    def find_food_id(self, name: str) -> Optional[str]:
        """Resolve a free-text food name/alias to a stable ``food_id``.

        Returns ``None`` when nothing matches. This supports the Food
        Normalization stage (multiple names mapping to one stable food id).
        Repositories that keep aliases override it; the default returns None.
        """
        return None

    def find_food_match(self, name: str) -> Optional[FoodMatch]:
        """Resolve ``name`` to match metadata (id + tier + score).

        The default classifies any ``find_food_id`` hit as a reliable ``alias``
        match; repositories that can classify the match type override this.
        """
        food_id = self.find_food_id(name)
        if food_id is None:
            return None
        return FoodMatch(food_id=food_id, tier="alias", score=1.0)


# ── CGM Repository ──────────────────────────────────────────────────────


@dataclass
class CGMConnectionRecord:
    """Persisted CGM provider connection state."""

    provider_name: str
    status: str = "not_connected"
    connected_at: Optional[str] = None
    last_sync_at: Optional[str] = None


@dataclass
class CGMReadingRecord:
    """Persisted CGM glucose reading."""

    id: Optional[int]
    provider: str
    glucose_value: float
    basal: float = 0.0
    hr: float = 0.0
    gsr: float = 0.0
    carb_input: float = 0.0
    bolus: float = 0.0
    timestamp: str = ""
    created_at: str = ""


@dataclass
class CGMPredictionRecord:
    """Persisted CGM prediction result."""

    id: Optional[int]
    prediction_30_min: float
    prediction_60_min: float
    readings_used: int
    predicted_at: str = ""


class CGMRepository(ABC):
    """Data-access interface for CGM connection state, readings, and predictions."""

    @abstractmethod
    def get_connection(self, provider_name: str) -> Optional[CGMConnectionRecord]:
        """Return the connection record for a provider, or None."""

    @abstractmethod
    def upsert_connection(self, record: CGMConnectionRecord) -> None:
        """Insert or update a provider connection record."""

    @abstractmethod
    def delete_connection(self, provider_name: str) -> None:
        """Remove a provider connection record."""

    @abstractmethod
    def insert_reading(self, record: CGMReadingRecord) -> int:
        """Persist a new CGM reading. Returns the inserted row id."""

    @abstractmethod
    def get_readings(
        self,
        provider: str,
        limit: int = 288,
    ) -> list[CGMReadingRecord]:
        """Return recent readings newest-first for a provider."""

    @abstractmethod
    def get_latest_prediction(self) -> Optional[CGMPredictionRecord]:
        """Return the most recent prediction, or None."""

    @abstractmethod
    def insert_prediction(self, record: CGMPredictionRecord) -> int:
        """Persist a new prediction. Returns the inserted row id."""


# ── Insulin Log Repository ──────────────────────────────────────────────


# Insulin type constants used across the codebase.
INSULIN_TYPE_RAPID = "rapid"
INSULIN_TYPE_REGULAR = "regular"
INSULIN_TYPE_NPH = "nph"

# Map user-facing insulin type strings to the internal type constants.
# Keys are lowercase.  Flutter sends values with parentheses stripped
# (e.g. "rapid-acting novorapid"), so both forms must be present.
INSULIN_TYPE_MAP: dict[str, str] = {
    # Profile screen types
    "rapid-acting": INSULIN_TYPE_RAPID,
    "short-acting": INSULIN_TYPE_REGULAR,
    "long-acting": INSULIN_TYPE_NPH,
    "premixed": INSULIN_TYPE_RAPID,
    "other": INSULIN_TYPE_RAPID,
    # Home screen types — with parentheses (original dropdown values)
    "regular (novolin r)": INSULIN_TYPE_REGULAR,
    "rapid-acting (novorapid)": INSULIN_TYPE_RAPID,
    "ultra-rapid (fiasp)": INSULIN_TYPE_RAPID,
    "humalog (lispro)": INSULIN_TYPE_RAPID,
    # Home screen types — without parentheses (Flutter strips them)
    "regular novolin r": INSULIN_TYPE_REGULAR,
    "rapid-acting novorapid": INSULIN_TYPE_RAPID,
    "ultra-rapid fiasp": INSULIN_TYPE_RAPID,
    "humalog lispro": INSULIN_TYPE_RAPID,
    # Short forms
    "rapid": INSULIN_TYPE_RAPID,
    "regular": INSULIN_TYPE_REGULAR,
    "nph": INSULIN_TYPE_NPH,
}


@dataclass
class InsulinLogRecord:
    """A single logged insulin dose."""

    id: Optional[int]
    dose_units: float
    insulin_type: str = INSULIN_TYPE_RAPID
    display_name: str = ""
    logged_at: str = ""
    created_at: str = ""


class InsulinLogRepository(ABC):
    """Data-access interface for insulin dose logs."""

    @abstractmethod
    def insert_log(self, record: InsulinLogRecord) -> int:
        """Persist a new insulin log entry. Returns the inserted row id."""

    @abstractmethod
    def get_logs_since(self, since: str) -> list[InsulinLogRecord]:
        """Return insulin logs at or after ``since`` (ISO-8601), newest-first."""

    @abstractmethod
    def get_all_logs(self, limit: int = 100) -> list[InsulinLogRecord]:
        """Return recent insulin logs, newest-first."""

    @abstractmethod
    def delete_log(self, log_id: int) -> None:
        """Remove an insulin log entry by id."""