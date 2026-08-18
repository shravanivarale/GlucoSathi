"""Shared byte fixtures and a fake Gemini recognizer for API tests."""

from types import SimpleNamespace

from app.services.gemini_service import FoodRecognizer, RecognizedFood

# Minimal-but-sniffable JPEG/PNG payloads (magic bytes only; the MVP only
# validates format, and Gemini is mocked in tests).
TINY_JPEG = (
    b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01\x01\x00\x00\x01\x00\x01\x00\x00"
    b"\xff\xdb\x00\x43\x00\x03\x02\x02\x02"
)
TINY_PNG = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01"
    b"\x08\x06\x00\x00\x00\x1f\x15\xc4\x89"
)
NOT_AN_IMAGE = b"this is definitely not an image file"


class FakeRecognizer(FoodRecognizer):
    """Returns a fixed food name without calling any API."""

    def __init__(self, food_name: str = "Poha") -> None:
        self.food_name = food_name

    def recognize(self, image_bytes: bytes, mime_type: str) -> RecognizedFood:
        return RecognizedFood(food_name=self.food_name)


class FakeRecognizerRaising(FoodRecognizer):
    """Simulates the recognition service failing."""

    def recognize(self, image_bytes: bytes, mime_type: str) -> RecognizedFood:
        from app.models.errors import FoodRecognitionError

        raise FoodRecognitionError("boom")