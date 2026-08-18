"""Cross-cutting concerns (config, security, logging).

Configuration (``config.py``) loads the project-root ``.env`` file and is the
single place the application reads secrets such as ``GEMINI_API_KEY``.
"""

from .config import (
    DEFAULT_GEMINI_MODEL,
    GEMINI_API_KEY,
    GEMINI_MODEL,
    get_secret,
    has_secret,
)

__all__ = [
    "GEMINI_API_KEY",
    "GEMINI_MODEL",
    "DEFAULT_GEMINI_MODEL",
    "get_secret",
    "has_secret",
]