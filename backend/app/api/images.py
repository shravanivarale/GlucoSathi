"""Image upload validation for the food recognition endpoints.

Images are validated in memory and never written to disk, so uploaded images
are never exposed publicly. Validation covers:

- JPEG/PNG only (declared content type + magic-byte sniffing),
- a maximum upload size (streamed so oversized files are not buffered fully).
"""

from __future__ import annotations

from fastapi import UploadFile

from .errors import ApiException

ALLOWED_IMAGE_MIME_TYPES = ("image/jpeg", "image/png")

# Normalize non-standard but common client MIME labels.
_MIME_ALIASES = {
    "image/jpg": "image/jpeg",
    "image/x-png": "image/png",
    "image/pjpeg": "image/jpeg",
}

# Reasonable MVP limit: 10 MB.
MAX_IMAGE_SIZE_BYTES = 10 * 1024 * 1024
_READ_CHUNK_BYTES = 1024 * 1024

_JPEG_MAGIC = b"\xff\xd8\xff"
_PNG_MAGIC = b"\x89PNG\r\n\x1a\n"


def sniff_image_mime(data: bytes) -> str | None:
    """Detect the actual image type from its leading bytes."""
    if data.startswith(_JPEG_MAGIC):
        return "image/jpeg"
    if data.startswith(_PNG_MAGIC):
        return "image/png"
    return None


async def read_validated_image(upload: UploadFile) -> tuple[bytes, str]:
    """Read ``upload`` into memory, validating type and size.

    Returns ``(image_bytes, mime_type)``. Raises ``ApiException`` with the
    ``INVALID_IMAGE`` (400) or ``IMAGE_TOO_LARGE`` (413) failure code when the
    file does not pass validation.
    """
    declared = (upload.content_type or "").strip().lower()
    if declared:
        declared = _MIME_ALIASES.get(declared, declared)
        if declared not in ALLOWED_IMAGE_MIME_TYPES:
            raise ApiException(
                400,
                "INVALID_IMAGE",
                "Unsupported image type; send a JPEG or PNG image",
            )

    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = await upload.read(_READ_CHUNK_BYTES)
        if not chunk:
            break
        total += len(chunk)
        if total > MAX_IMAGE_SIZE_BYTES:
            raise ApiException(
                413,
                "IMAGE_TOO_LARGE",
                f"Image exceeds the {MAX_IMAGE_SIZE_BYTES // (1024 * 1024)} MB limit",
            )
        chunks.append(chunk)

    data = b"".join(chunks)
    if not data:
        raise ApiException(400, "INVALID_IMAGE", "No image content was uploaded")

    mime_type = sniff_image_mime(data)
    if mime_type is None:
        raise ApiException(
            400,
            "INVALID_IMAGE",
            "Uploaded file is not a valid JPEG or PNG image",
        )

    return data, mime_type


def read_validated_image_sync(data: bytes, content_type: str | None) -> tuple[bytes, str]:
    """Synchronous validation helper (used directly by tests).

    Mirrors the async path: type+magic-byte validation and size check, without
    any dependency on ASGI machinery.
    """
    declared = (content_type or "").strip().lower()
    if declared:
        declared = _MIME_ALIASES.get(declared, declared)
        if declared not in ALLOWED_IMAGE_MIME_TYPES:
            raise ApiException(
                400,
                "INVALID_IMAGE",
                "Unsupported image type; send a JPEG or PNG image",
            )
    if not data:
        raise ApiException(400, "INVALID_IMAGE", "No image content was uploaded")
    if len(data) > MAX_IMAGE_SIZE_BYTES:
        raise ApiException(
            413,
            "IMAGE_TOO_LARGE",
            f"Image exceeds the {MAX_IMAGE_SIZE_BYTES // (1024 * 1024)} MB limit",
        )
    mime_type = sniff_image_mime(data)
    if mime_type is None:
        raise ApiException(
            400,
            "INVALID_IMAGE",
            "Uploaded file is not a valid JPEG or PNG image",
        )
    return data, mime_type