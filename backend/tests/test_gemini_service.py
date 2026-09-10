"""Gemini Vision service tests — the Gemini API is fully mocked.

No real Gemini call is ever made. ``google.genai.Client`` is replaced with a
fake that returns a canned structured response, exercising the service's
call-building, response parsing and error paths.
"""

from types import SimpleNamespace

import pytest

from app.models.errors import FoodRecognitionError
from app.services.gemini_service import GeminiVisionRecognizer

from tests.image_helpers import TINY_JPEG


def _fake_client_factory(response, calls=None):
    if calls is None:
        calls = []

    class _FakeModels:
        def generate_content(self, model, contents, config):
            calls.append((model, contents, config))
            return response

    class _FakeClient:
        def __init__(self, api_key=None, http_options=None):
            self.models = _FakeModels()

    return _FakeClient, calls


def _structured_response(food_names):
    """Build a fake Gemini response with a parsed list of food items."""
    if isinstance(food_names, str):
        food_names = [food_names]
    items = [SimpleNamespace(name=n) for n in food_names]
    return SimpleNamespace(parsed=items, text=None)


def _text_response(food_names):
    """Build a fake Gemini response with JSON text containing food items."""
    import json

    if isinstance(food_names, str):
        food_names = [food_names]
    return SimpleNamespace(
        parsed=None,
        text=json.dumps([{"name": n} for n in food_names]),
    )


def test_recognize_uses_configured_model_and_sends_image(monkeypatch):
    calls = []
    FakeClient, calls = _fake_client_factory(_structured_response("Poha"), calls)
    monkeypatch.setattr("google.genai.Client", FakeClient)
    recognizer = GeminiVisionRecognizer(api_key="test-key", model="gemini-2.5-flash")

    result = recognizer.recognize(TINY_JPEG, "image/jpeg")

    assert len(result) == 1
    assert result[0].food_name == "Poha"
    assert calls and calls[0][0] == "gemini-2.5-flash"
    # The image bytes and MIME type are sent as an inline data part.
    part = calls[0][1][0]
    assert part.inline_data.data == TINY_JPEG
    assert part.inline_data.mime_type == "image/jpeg"
    # Structured output is requested.
    config = calls[0][2]
    assert config.response_mime_type == "application/json"
    assert config.response_schema is not None


def test_recognize_configures_timeout_and_retries(monkeypatch):
    """The client is created with a bounded timeout and transient-error retries.

    Without these the SDK defaults to a single attempt and no timeout, which
    surfaced as intermittent 502s on Gemini overload/slowness.
    """
    captured = {}

    class _FakeModels:
        def generate_content(self, model, contents, config):
            return _structured_response("Poha")

    class _FakeClient:
        def __init__(self, api_key=None, http_options=None):
            captured["http_options"] = http_options
            self.models = _FakeModels()

    monkeypatch.setattr("google.genai.Client", _FakeClient)
    recognizer = GeminiVisionRecognizer(api_key="test-key")
    recognizer.recognize(TINY_JPEG, "image/jpeg")

    opts = captured["http_options"]
    assert opts is not None
    assert opts.timeout == 60 * 1000
    assert opts.retry_options is not None
    assert opts.retry_options.attempts == 4
    # 429 RESOURCE_EXHAUSTED must NOT be retried (wasted quota); transient 5xx
    # statuses stay retryable.
    assert opts.retry_options.http_status_codes == [408, 500, 502, 503, 504]
    assert 429 not in opts.retry_options.http_status_codes
    assert 503 in opts.retry_options.http_status_codes


def test_recognize_defaults_model_from_config(monkeypatch):
    monkeypatch.setenv("GEMINI_MODEL", "gemini-2.5-flash")
    calls = []
    FakeClient, calls = _fake_client_factory(_structured_response("Poha"), calls)
    monkeypatch.setattr("google.genai.Client", FakeClient)
    recognizer = GeminiVisionRecognizer(api_key="test-key")
    recognizer.recognize(TINY_JPEG, "image/jpeg")
    assert calls and calls[0][0] == "gemini-2.5-flash"


def test_recognize_extracts_single_food_item(monkeypatch):
    FakeClient, _ = _fake_client_factory(_structured_response("Masala dosa"))
    monkeypatch.setattr("google.genai.Client", FakeClient)
    recognizer = GeminiVisionRecognizer(api_key="test-key")
    result = recognizer.recognize(TINY_JPEG, "image/jpeg")
    assert len(result) == 1
    assert result[0].food_name == "Masala dosa"


def test_recognize_extracts_multiple_food_items(monkeypatch):
    FakeClient, _ = _fake_client_factory(
        _structured_response(["Rice", "Chicken curry", "Roti"])
    )
    monkeypatch.setattr("google.genai.Client", FakeClient)
    recognizer = GeminiVisionRecognizer(api_key="test-key")
    result = recognizer.recognize(TINY_JPEG, "image/jpeg")
    assert len(result) == 3
    assert [r.food_name for r in result] == ["Rice", "Chicken curry", "Roti"]


def test_recognize_falls_back_to_json_text(monkeypatch):
    FakeClient, _ = _fake_client_factory(_text_response("Rajma Chawal"))
    monkeypatch.setattr("google.genai.Client", FakeClient)
    recognizer = GeminiVisionRecognizer(api_key="test-key")
    result = recognizer.recognize(TINY_JPEG, "image/jpeg")
    assert len(result) == 1
    assert result[0].food_name == "Rajma Chawal"


def test_recognize_falls_back_to_json_text_multiple(monkeypatch):
    FakeClient, _ = _fake_client_factory(
        _text_response(["Poha", "Tea"])
    )
    monkeypatch.setattr("google.genai.Client", FakeClient)
    recognizer = GeminiVisionRecognizer(api_key="test-key")
    result = recognizer.recognize(TINY_JPEG, "image/jpeg")
    assert len(result) == 2
    assert result[0].food_name == "Poha"
    assert result[1].food_name == "Tea"


def test_recognize_rejects_unusable_response(monkeypatch):
    bad = SimpleNamespace(parsed=None, text="I cannot see any food in this image.")
    FakeClient, _ = _fake_client_factory(bad)
    monkeypatch.setattr("google.genai.Client", FakeClient)
    recognizer = GeminiVisionRecognizer(api_key="test-key")
    with pytest.raises(FoodRecognitionError):
        recognizer.recognize(TINY_JPEG, "image/jpeg")


def test_recognize_rejects_empty_array(monkeypatch):
    FakeClient, _ = _fake_client_factory(_structured_response([]))
    monkeypatch.setattr("google.genai.Client", FakeClient)
    recognizer = GeminiVisionRecognizer(api_key="test-key")
    with pytest.raises(FoodRecognitionError, match="no usable food names"):
        recognizer.recognize(TINY_JPEG, "image/jpeg")


def test_recognize_raises_without_api_key(monkeypatch):
    monkeypatch.delenv("GEMINI_API_KEY", raising=False)
    recognizer = GeminiVisionRecognizer(api_key=None, model="x")
    with pytest.raises(FoodRecognitionError, match="GEMINI_API_KEY"):
        recognizer.recognize(TINY_JPEG, "image/jpeg")


def test_recognize_raises_on_unsupported_mime(monkeypatch):
    FakeClient, _ = _fake_client_factory(_structured_response("Poha"))
    monkeypatch.setattr("google.genai.Client", FakeClient)
    recognizer = GeminiVisionRecognizer(api_key="test-key")
    with pytest.raises(FoodRecognitionError, match="Unsupported image type"):
        recognizer.recognize(TINY_JPEG, "image/webp")


def test_recognize_wraps_sdk_exceptions(monkeypatch):
    class _Boom:
        def __init__(self):
            pass

        @property
        def models(self):
            raise RuntimeError("network down")

    class _BoomClient:
        def __init__(self, api_key=None, http_options=None):
            self._models = _Boom()

        @property
        def models(self):
            return self._models

    monkeypatch.setattr("google.genai.Client", _BoomClient)
    recognizer = GeminiVisionRecognizer(api_key="test-key")
    with pytest.raises(FoodRecognitionError):
        recognizer.recognize(TINY_JPEG, "image/jpeg")


def test_recognize_keeps_client_alive_through_request(monkeypatch):
    """Regression: no closed-client error when a request is made.

    The google-genai SDK closes a sync ``Client`` (and its httpx transport) in
    ``__del__``. A transient ``Client(...).models.generate_content(...)`` gets
    garbage-collected -- and thus closed -- as soon as ``.models`` resolves, which
    fails the request with "Cannot send a request, as the client has been closed".

    This fake reproduces that lifecycle (close-on-``__del__``) and asserts the
    recognizer holds its client alive for the entire mocked request.
    """
    created = []
    used = []

    class _FakeModels:
        def __init__(self, client):
            self._client = client

        def generate_content(self, model, contents, config):
            assert not self._client._closed, "client closed before request"
            used.append(model)
            return _structured_response("Poha")

    class _FakeClient:
        def __init__(self, api_key=None, http_options=None):
            created.append(api_key)
            self._closed = False
            self.models = _FakeModels(self)

        def close(self):
            self._closed = True

        def __del__(self):
            self.close()

    monkeypatch.setattr("google.genai.Client", _FakeClient)
    recognizer = GeminiVisionRecognizer(api_key="test-key", model="gemini-2.5-flash")

    first = recognizer.recognize(TINY_JPEG, "image/jpeg")
    second = recognizer.recognize(TINY_JPEG, "image/jpeg")

    assert first[0].food_name == "Poha"
    assert second[0].food_name == "Poha"
    assert used == ["gemini-2.5-flash", "gemini-2.5-flash"]
    # The client is created once and reused (not rebuilt per request).
    assert created == ["test-key"]


def test_recognize_close_releases_shared_client(monkeypatch):
    created = []

    class _FakeClient:
        def __init__(self, api_key=None, http_options=None):
            created.append(api_key)
            self._closed = False
            self.models = _FakeModels(self)

        def close(self):
            self._closed = True

    class _FakeModels:
        def __init__(self, client):
            self._client = client

        def generate_content(self, model, contents, config):
            assert not self._client._closed, "client closed before request"
            return _structured_response("Poha")

    monkeypatch.setattr("google.genai.Client", _FakeClient)
    recognizer = GeminiVisionRecognizer(api_key="test-key")

    recognizer.recognize(TINY_JPEG, "image/jpeg")
    recognizer.close()

    # Idempotent and safe to call again (e.g. at shutdown).
    recognizer.close()
    assert created == ["test-key"]
