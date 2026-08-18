"""API-layer exceptions and their HTTP error envelope.

Every API failure is returned with the project's standard failure envelope
(``docs/failure-cases.md``):

    {"success": false, "data": null, "error": {"code": ..., "message": ...}}
"""

from __future__ import annotations

from fastapi import Request
from fastapi.responses import JSONResponse


class ApiException(Exception):
    """An API error carrying the HTTP status and machine-readable failure code."""

    def __init__(self, status_code: int, code: str, message: str) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message


def _error_body(code: str, message: str) -> dict:
    return {
        "success": False,
        "data": None,
        "error": {"code": code, "message": message},
    }


async def api_exception_handler(request: Request, exc: ApiException) -> JSONResponse:
    return JSONResponse(
        status_code=exc.status_code,
        content=_error_body(exc.code, exc.message),
    )