"""Gemini Vision food recognition service.

This module is the ONLY place that talks to Google's Gemini API. Its single
responsibility is identifying every distinct food/dish visible in an image and
returning a list of concise canonical food names — it never produces nutrition
values.

The concrete class is isolated behind the ``FoodRecognizer`` interface so the
rest of the application (routers, analyzer pipeline, tests) depends on the
interface and can mock it without calling the real Gemini API.
"""

from __future__ import annotations

import abc
import json

from dataclasses import dataclass
from typing import List, Optional

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

# Gemini returns an array of food items; each item must have a "name" field.
# This schema forces Gemini to return structured per-item names rather than a
# single combined string, so the backend can match each food independently.
_RESPONSE_SCHEMA = {
    "type": "ARRAY",
    "items": {
        "type": "OBJECT",
        "properties": {
            "name": {"type": "STRING"},
        },
        "required": ["name"],
    },
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
    "You identify foods in meal images for an Indian nutrition app. "
    "Look at the image and list EVERY distinct food or dish visible on the "
    "plate. For each food, return just its name as it would appear in the "
    "Indian Nutrient Databank (INDB). "
    "Use short canonical names like \"Rice\", \"Chicken curry\", \"Roti\", "
    "\"Dal\", \"Salad\". Return ONE entry per food item. "
    "Never combine multiple foods into a single name. "
    "Never report amounts, weights, portions or cooking instructions. "
    "Never report nutrition values such as calories, carbohydrates, protein or "
    "fat. "
    "Never add explanations, disclaimers or extra text."
)


@dataclass
class RecognizedFood:
    """A single food identified in an image."""

    food_name: str


class FoodRecognizer(abc.ABC):
    """Interface implemented by the Gemini recognizer (mockable in tests)."""

    @abc.abstractmethod
    def recognize(self, image_bytes: bytes, mime_type: str) -> List[RecognizedFood]:
        """Return the list of foods identified in ``image_bytes``.

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

    def recognize(self, image_bytes: bytes, mime_type: str) -> List[RecognizedFood]:
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

        items = self._extract_food_items(response)
        if not items:
            raise FoodRecognitionError(
                "Gemini returned no usable food names for the image"
            )
        return items

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
    def _extract_food_items(response) -> List[RecognizedFood]:
        """Extract food items from a Gemini structured-output response.

        Prefers the SDK-parsed object (``response.parsed``) and falls back to
        parsing ``response.text`` as JSON -- this keeps the service robust
        across SDK versions and model behaviours.
        """
        parsed = getattr(response, "parsed", None)
        if parsed is not None:
            # parsed may be a list of objects (structured output) or a single
            # object wrapping a list.  Handle both forms.
            items = parsed if isinstance(parsed, list) else getattr(parsed, "foods", [])
            results: List[RecognizedFood] = []
            for item in items:
                name = getattr(item, "name", None)
                if name:
                    results.append(RecognizedFood(food_name=str(name).strip()))
            if results:
                return results

        text = getattr(response, "text", None)
        if not text:
            return []
        try:
            payload = json.loads(text)
        except (json.JSONDecodeError, TypeError):
            return []
        # payload may be a list of {"name": "..."} dicts or a dict wrapping a
        # list under a "foods" key.
        if isinstance(payload, list):
            seq = payload
        elif isinstance(payload, dict):
            seq = payload.get("foods", [])
        else:
            return []
        results = []
        for entry in seq:
            if isinstance(entry, dict):
                name = entry.get("name")
                if name:
                    results.append(RecognizedFood(food_name=str(name).strip()))
        return results
