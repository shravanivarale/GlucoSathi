"""HTTP routes for the Food Image Upload + Food Recognition MVP.

Endpoints (versioned under ``/api/v1/foods``):

- ``POST /api/v1/foods/recognize`` — upload a food image, get the recognized
  food name from Gemini Vision.
- ``POST /api/v1/foods/analyze`` — full workflow: image -> Gemini Vision ->
  food name -> INDB search -> nutrition result.

Both endpoints accept ``multipart/form-data`` with a single ``image`` file
(JPEG/PNG). Images are handled in memory and never stored on disk.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, File, UploadFile
from starlette.concurrency import run_in_threadpool

from ..models.errors import FoodRecognitionError
from ..schemas.food_api import FoodAnalyzeResponse, FoodRecognizeResponse
from ..services.food_analyzer import FoodAnalyzer
from .dependencies import get_food_analyzer
from .errors import ApiException
from .images import read_validated_image

router = APIRouter(prefix="/api/v1/foods", tags=["foods"])


@router.post(
    "/recognize",
    response_model=FoodRecognizeResponse,
    summary="Recognize the food in an uploaded image",
)
async def recognize_food(
    image: UploadFile = File(...),
    analyzer: FoodAnalyzer = Depends(get_food_analyzer),
) -> FoodRecognizeResponse:
    image_bytes, mime_type = await _load_image(image)
    try:
        # Gemini recognition is blocking; run it in the threadpool so a slow
        # call never stalls the event loop (health checks, other requests).
        result = await run_in_threadpool(analyzer.recognize, image_bytes, mime_type)
    except FoodRecognitionError as exc:
        _raise_recognition_error(exc)
    return FoodRecognizeResponse(recognized_food=result.recognized_food)


@router.post(
    "/analyze",
    response_model=FoodAnalyzeResponse,
    response_model_exclude_none=True,
    summary="Recognize a food and return its INDB nutrition",
)
async def analyze_food(
    image: UploadFile = File(...),
    analyzer: FoodAnalyzer = Depends(get_food_analyzer),
) -> FoodAnalyzeResponse:
    image_bytes, mime_type = await _load_image(image)
    try:
        # Gemini recognition is blocking; run it in the threadpool so a slow
        # call never stalls the event loop (health checks, other requests).
        result = await run_in_threadpool(analyzer.analyze, image_bytes, mime_type)
    except FoodRecognitionError as exc:
        _raise_recognition_error(exc)
    return FoodAnalyzeResponse(
        recognized_food=result.recognized_food,
        matched=result.matched,
        food_id=result.food_id,
        food_name=result.food_name,
        nutrition=result.nutrition,
        message=result.message,
    )


async def _load_image(image: UploadFile) -> tuple[bytes, str]:
    return await read_validated_image(image)


def _raise_recognition_error(exc: FoodRecognitionError) -> None:
    raise ApiException(
        502,
        "ANALYSIS_FAILED",
        exc.args[0] if exc.args else "Food recognition service failed",
    )