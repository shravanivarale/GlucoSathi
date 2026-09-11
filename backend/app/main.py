"""GlucoSaathi FastAPI application entry point.

Run with::

    uvicorn app.main:app --reload

Mounts the versioned API routers and the health check. Safe to run without a
GEMINI_API_KEY for everything except the Gemini-backed endpoints.
"""

from __future__ import annotations

from contextlib import asynccontextmanager

from fastapi import FastAPI

from .api.dependencies import close_food_recognizer
from .api.errors import ApiException, api_exception_handler
from .api.glucose import router as glucose_router
from .api.foods import router as foods_router
from .api.cgm import router as cgm_router
from .api.insulin import router as insulin_router


@asynccontextmanager
async def lifespan(_: FastAPI):
    """Release long-lived resources (e.g. the shared Gemini client) on shutdown."""
    yield
    close_food_recognizer()


app = FastAPI(
    title="GlucoSaathi Backend",
    version="0.1.0",
    description="Food Image Upload + Food Recognition MVP backend.",
    lifespan=lifespan,
)

app.add_exception_handler(ApiException, api_exception_handler)

app.include_router(glucose_router)
app.include_router(foods_router)
app.include_router(cgm_router)
app.include_router(insulin_router)

@app.get("/health", tags=["health"], summary="Service health check")
def health() -> dict[str, str]:
    return {"status": "ok"}