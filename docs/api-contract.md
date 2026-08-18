# Food Recognition API Contract

This document is the source-of-truth contract between the Flutter client and the FastAPI backend for the Food Recognition MVP.

## Architectural principle

Recognition and nutrition are decoupled:

- The **recognition model** (initially Gemini Vision, later our own ML model) identifies the food and estimates the serving size.
- The **nutrition database** (PostgreSQL, e.g. INDB) is the sole authority for nutrition values.

The recognition model must never be treated as authoritative for carbohydrates, protein, fat, calories, or fiber. The nutrition layer stays independent of whichever recognition model is in use.

## Endpoints

All endpoints below are implemented and versioned under `/api/v1`.

- `GET  /health` — service health check.
- `POST /api/v1/foods/recognize` — upload a food image, get the recognized food name only.
- `POST /api/v1/foods/analyze` — full workflow: image → recognition → INDB nutrition.

### Health check

```
GET /health
```

`HTTP 200 OK`

```json
{ "status": "ok" }
```

### Recognize a food

```
POST /api/v1/foods/recognize
```

#### Request

- `Content-Type`: `multipart/form-data`
- Body field:

| Field | Type   | Required | Description              |
|-------|--------|----------|--------------------------|
| image | `file` | yes      | JPEG/PNG image of the meal |

#### Success response

`HTTP 200 OK`

```json
{
  "recognized_food": "Rajma Chawal"
}
```

`recognized_food` is the canonical food name produced by Gemini Vision (and is
safe to search against the INDB-derived alias index).

### Analyze a food (recognize + nutrition)

```
POST /api/v1/foods/analyze
```

#### Request

- `Content-Type`: `multipart/form-data`
- Body field:

| Field | Type   | Required | Description              |
|-------|--------|----------|--------------------------|
| image | `file` | yes      | JPEG/PNG image of the meal |

#### Success response (matched)

`HTTP 200 OK`

```json
{
  "recognized_food": "Poha",
  "matched": true,
  "food_id": "BFP044",
  "food_name": "Poha",
  "nutrition": {
    "carb_g": 35.048,
    "protein_g": 6.085,
    "fat_g": 14.138,
    "fibre_g": 3.716,
    "energy_kcal": 294.526,
    "basis": "per_100g",
    "nutrition_source": "INDB"
  }
}
```

`nutrition` uses the actual INDB columns on a per-100g basis; `carb_g` is the
key MVP field. Values always come from the INDB-backed database — never from
the recognition model, and never fabricated when no reliable match exists.

#### Success response (no reliable INDB match)

`HTTP 200 OK`

```json
{
  "recognized_food": "Rajma Chawal",
  "matched": false,
  "message": "Food not found in nutrition database"
}
```

`Rajma Chawal` is not an exact INDB entry (the closest INDB food is "Kidney
bean curry (Rajmah curry)"), so an honest unmatched response is returned
rather than inventing nutrition values.

#### Image validation

Both POST endpoints share the same validation: JPEG/PNG only (declared MIME
type + magic-byte sniffing) and a 10 MB maximum. Images are processed in
memory and are never stored on disk.

### Earlier (pre-MVP) contract

The earlier design documented a single `POST /api/v1/food/analyze` that
returned a `success`/`data`/`error` envelope with `MealResult`
(`meal_id`, `food_id`, `food_name`, `recognition_confidence`,
`estimated_serving_size_g`, `nutrition`) and a per-serving nutrition estimate.
That contract is superseded for the Food Image Upload + Food Recognition MVP by
the `/api/v1/foods/*` endpoints above. Schemas for the older design remain in
`backend/app/schemas/meal.py`; `lib/models/meal_result.dart` still models its
`MealResult` shape and can be used by the Flutter client to parse a future
serving-aware endpoint.

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