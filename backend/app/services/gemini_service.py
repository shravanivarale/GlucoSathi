"""Gemini Vision food recognition service.

This module is the ONLY place that talks to Google's Gemini API. Its single
responsibility is identifying the main food/dish in an image and returning a
concise canonical food name — it never produces nutrition values.

The concrete class is isolated behind the ``FoodRecognizer`` interface so the
rest of the application (routers, analyzer pipeline, tests) depends on the
interface and can mock it without calling the real Gemini API.
"""

from __future__ import annotations

import abc
import json

from dataclasses import dataclass
from typing import Optional

from ..core.config import (
    DEFAULT_GEMINI_MODEL,
    GEMINI_API_KEY,
    GEMINI_MODEL,
    get_secret,
    has_secret,
)
from ..models.errors import FoodRecognitionError

# Supported image MIME types accepted by Gemini's inline image part.
SUPPORTED_IMAGE_MIME_TYPES = ("image/jpeg", "image/png")

# Gemini returns the food name here; all other fields are rejected by the
# response schema so Gemini cannot drift into nutrition/extra text.
_RESPONSE_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "food_name": {"type": "STRING"},
    },
    "required": ["food_name"],
}

# Bound each Gemini request and retry transient failures. Without these the
# google-genai SDK defaults to a single attempt with no timeout, so a slow or
# temporarily overloaded Gemini surfaced as intermittent 502s and app-side
# "took too long" failures.
GEMINI_TIMEOUT_SECONDS = 60
GEMINI_RETRY_ATTEMPTS = 4  # 1 initial call + up to 3 backoff retries.

# Status codes the SDK should retry. 429 RESOURCE_EXHAUSTED is deliberately
# excluded: it means the account's per-day free-tier quota is spent (20
# requests/day for the model), which never recovers within a request — retrying
# it would only waste the few remaining requests and delay the real error.
# Transient 5xx and timeouts are kept. httpx connect/timeout errors are always
# retried by the SDK regardless of this list.
GEMINI_RETRYABLE_STATUS_CODES = [408, 500, 502, 503, 504]

_PROMPT = (
    "You identify the food in meal images for an Indian nutrition app. "
    "Look at the image and name the SINGLE main food/dish it shows. "
    "Return a concise canonical food name (for example \"Rajma Chawal\" or "
    "\"Masala dosa\") that is likely to exist in the Indian Nutrient Databank "
    "(INDB). "
    "Never report amounts, weights, portions or cooking instructions. "
    "Never report nutrition values such as calories, carbohydrates, protein or "
    "fat. "
    "Never add explanations, disclaimers or extra text."
)


@dataclass
class RecognizedFood:
    """The main food identified in an image."""

    food_name: str


class FoodRecognizer(abc.ABC):
    """Interface implemented by the Gemini recognizer (mockable in tests)."""

    @abc.abstractmethod
    def recognize(self, image_bytes: bytes, mime_type: str) -> RecognizedFood:
        """Return the canonical food name identified in ``image_bytes``.

        Raises ``FoodRecognitionError`` when the image cannot be recognized.
        """


class GeminiVisionRecognizer(FoodRecognizer):
    """Gemini Vision implementation using the official ``google-genai`` SDK.

    ``api_key`` and ``model`` override the application configuration; both
    default to values read from ``backend/app/core/config.py`` (project-root
    ``.env``). The API key is never printed or logged.
    """

    def __init__(self, api_key: Optional[str] = None, model: Optional[str] = None) -> None:
        self._api_key = api_key if api_key is not None else get_secret(GEMINI_API_KEY)
        self._model = model or get_secret(GEMINI_MODEL) or DEFAULT_GEMINI_MODEL
        # A single Gemini client, created lazily and reused for every request.
        # The SDK closes a `Client` (and its underlying httpx transport) in
        # `__del__`; holding the client here keeps it alive for the full request
        # and prevents a transient client from being closed mid-call.
        self._client = None

    def recognize(self, image_bytes: bytes, mime_type: str) -> RecognizedFood:
        if not self._api_key:
            raise FoodRecognitionError(
                "GEMINI_API_KEY is not configured; cannot call Gemini Vision"
            )
        if mime_type not in SUPPORTED_IMAGE_MIME_TYPES:
            raise FoodRecognitionError(
                f"Unsupported image type {mime_type!r} for Gemini Vision"
            )
        try:
            from google.genai import Client, types

            client = self._client
            if client is None:
                client = self._client = Client(
                    api_key=self._api_key,
                    http_options=types.HttpOptions(
                        timeout=GEMINI_TIMEOUT_SECONDS * 1000,
                        retry_options=types.HttpRetryOptions(
                            attempts=GEMINI_RETRY_ATTEMPTS,
                            http_status_codes=GEMINI_RETRYABLE_STATUS_CODES,
                        ),
                    ),
                )

            response = client.models.generate_content(
                model=self._model,
                contents=[
                    types.Part.from_bytes(data=image_bytes, mime_type=mime_type)
                ],
                config=types.GenerateContentConfig(
                    response_mime_type="application/json",
                    response_schema=_RESPONSE_SCHEMA,
                    temperature=0.0,
                ),
            )
        except Exception as exc:  # SDK/transport errors -> recognition failure
            raise FoodRecognitionError(
                f"Gemini Vision recognition failed: {exc}"
            ) from exc

        food_name = self._extract_food_name(response)
        if not food_name:
            raise FoodRecognitionError(
                "Gemini returned no usable food name for the image"
            )
        return RecognizedFood(food_name=food_name)

    def close(self) -> None:
        """Release the shared Gemini client (idempotent).

        Called once at application shutdown. Safe because each ``recognize``
        call returns only after the client has finished with the request.
        """
        client = self._client
        self._client = None
        if client is not None:
            close = getattr(client, "close", None)
            if callable(close):
                close()

    @staticmethod
    def _extract_food_name(response) -> Optional[str]:
        """Extract the food name from a Gemini structured-output response.

        Prefers the SDK-parsed object (``response.parsed``) and falls back to
        parsing ``response.text`` as JSON -- this keeps the service robust
        across SDK versions and model behaviours.
        """
        parsed = getattr(response, "parsed", None)
        if parsed is not None:
            value = getattr(parsed, "food_name", None)
            if value:
                return str(value).strip()

        text = getattr(response, "text", None)
        if not text:
            return None
        try:
            payload = json.loads(text)
        except (json.JSONDecodeError, TypeError):
            return None
        if isinstance(payload, dict):
            value = payload.get("food_name")
            if value:
                return str(value).strip()
        return None