# Food Recognition API Contract

This document is the source-of-truth contract between the Flutter client and the FastAPI backend for the Food Recognition MVP.

## Architectural principle

Recognition and nutrition are decoupled:

- The **recognition model** (initially Gemini Vision, later our own ML model) identifies the food and estimates the serving size.
- The **nutrition database** (PostgreSQL, e.g. INDB) is the sole authority for nutrition values.

The recognition model must never be treated as authoritative for carbohydrates, protein, fat, calories, or fiber. The nutrition layer stays independent of whichever recognition model is in use.

## Endpoint

```
POST /api/v1/food/analyze
```

### Request

- `Content-Type`: `multipart/form-data`
- Body field:

| Field | Type   | Required | Description              |
|-------|--------|----------|--------------------------|
| image | `file` | yes      | JPEG/PNG image of the meal |

The contract covers only the request shape. Actual image upload / recognition is implemented in a later step.

### Success response

`HTTP 200 OK`

```json
{
  "success": true,
  "data": {
    "meal_id": "uuid",
    "food_id": "food-id",
    "food_name": "Rajma Chawal",
    "recognition_confidence": 0.91,
    "estimated_serving_size_g": 250,
    "nutrition": {
      "carbs_g": 68.0,
      "protein_g": 14.0,
      "fat_g": 10.0,
      "fiber_g": 8.0,
      "calories": 420.0,
      "nutrition_source": "INDB"
    }
  },
  "error": null
}
```

#### `data` fields

The `data` object consists of three distinct layers:

1. **Recognition information** — what the recognition model identified.
2. **Estimated portion** — the serving size estimate.
3. **Nutrition information** — values from the nutrition database.

| Field                      | Type   | Description                                                          |
|----------------------------|--------|----------------------------------------------------------------------|
| `meal_id`                  | string | Stable UUID assigned by the backend                                 |
| `food_id`                  | string | Identifier of the recognized food in the nutrition database          |
| `food_name`                | string | Human-readable food name, e.g. "Rajma Chawal"                        |
| `recognition_confidence`   | number | Application/model confidence score in range `0.0`–`1.0`. **Not** a medically validated probability. |
| `estimated_serving_size_g` | number | Estimated portion size in grams from the image/recognition stage. **This is an estimate.** |
| `nutrition`                | object | Nutrition values for the estimated serving size (see below)          |

`nutrition` fields:

| Field             | Type   | Description                                                    |
|-------------------|--------|----------------------------------------------------------------|
| `carbs_g`         | number | Carbohydrates in grams, from the nutrition database            |
| `protein_g`       | number | Protein in grams, from the nutrition database                  |
| `fat_g`           | number | Fat in grams, from the nutrition database                      |
| `fiber_g`         | number | Dietary fiber in grams, from the nutrition database            |
| `calories`        | number | Total energy in kilocalories, from the nutrition database      |
| `nutrition_source`| string | Nutrition database id (e.g. `INDB`) the values were taken from |

Nutrition values always correspond to `estimated_serving_size_g` and always come from the nutrition database — never from the recognition model (Gemini/ML).

### Failure responses

`HTTP 4xx` / `5xx`

```json
{
  "success": false,
  "data": null,
  "error": {
    "code": "FOOD_NOT_RECOGNIZED",
    "message": "We couldn't identify the food in this image."
  }
}
```

See [`docs/failure-cases.md`](./failure-cases.md) for the full list of error codes and their HTTP statuses.

### Client mapping

The Flutter app parses `data` into `MealResult` (`lib/models/meal_result.dart`) and maps error codes to sealed failure subtypes in `lib/core/errors/app_failure.dart`.

Backend response schemas: `backend/app/schemas/meal.py` (`MealResult`, `NutritionInfo`, `ApiError`, `FoodAnalyzeSuccess`, `FoodAnalyzeError`).