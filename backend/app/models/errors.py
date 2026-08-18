"""Domain-level errors raised by the nutrition data layer.

These map 1:1 to error codes documented in ``docs/failure-cases.md``:
``FOOD_NOT_FOUND`` and ``NUTRITION_DATA_NOT_FOUND``.
"""


class NutritionDataError(Exception):
    """Base error for the nutrition data layer."""


class FoodNotFoundError(NutritionDataError):
    """Raised when no food matches the given ``food_id``.

    Corresponds to the ``FOOD_NOT_FOUND`` failure code.
    """


class NutritionDataNotFoundError(NutritionDataError):
    """Raised when a food exists but its nutrition values are unavailable.

    Corresponds to the ``NUTRITION_DATA_NOT_FOUND`` failure code.
    """


class FoodRecognitionError(Exception):
    """Raised when the recognition service (e.g. Gemini Vision) fails or the
    image cannot be identified as food.

    Maps to the ``FOOD_NOT_RECOGNIZED`` / ``ANALYSIS_FAILED`` failure codes.
    """
