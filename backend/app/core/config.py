"""Application configuration, loaded from the project-root ``.env`` file.

The backend has no runtime entry point yet (API routes are not implemented),
so configuration lives in this - the designated _config_ layer. This module
loads ``<repo-root>/.env`` into the process environment on import; it never
prints, logs, or hardcodes secret values. Existing environment variables take
precedence over the file (matching standard ``dotenv`` behaviour).
"""

import os
from pathlib import Path

# repo root = backend/app/core/../../.. -> project root containing ".env".
_PROJECT_ROOT = Path(__file__).resolve().parents[3]
_ENV_FILE = _PROJECT_ROOT / ".env"

# Secret used by the Gemini recognition integration.
GEMINI_API_KEY = "GEMINI_API_KEY"

# Environment variable that selects the Gemini model for image understanding.
GEMINI_MODEL = "GEMINI_MODEL"
# Default model when GEMINI_MODEL is not set. Image-capable Gemini model
# supported by the installed google-genai SDK.
DEFAULT_GEMINI_MODEL = "gemini-3.6-flash"


def _load_dotenv(path: Path) -> None:
    """Load ``KEY=VALUE`` lines from ``path`` into ``os.environ``.

    Skips blank lines and comments; strips surrounding quotes; does not
    override variables already present in the environment.
    """
    if not path.is_file():
        return
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        if not key or key in os.environ:
            continue
        os.environ[key] = value.strip().strip('"').strip("'")


_load_dotenv(_ENV_FILE)


def get_secret(name: str) -> str | None:
    """Return a secret's value from the environment, or ``None`` if unset."""
    return os.environ.get(name)


def has_secret(name: str) -> bool:
    """Return whether a secret is present without revealing its value."""
    return bool(get_secret(name))