# Architecture

High-level data flow for the Food Recognition MVP.

```
Flutter (Android)
      │  POST /api/v1/food/analyze (multipart: image)
      ▼
FastAPI (backend/app)              ── router layer (backend/app/api)
      │
      ▼
Food Recognition                   ── initially Gemini Vision, later team ML model
      │  food_id + food_name + recognition_confidence
      │  + estimated_serving_size_g
      ▼
Food Normalization                 ── mapping label → canonical food entry
      │
      ▼
Nutrition Database                ── PostgreSQL (e.g. INDB)
      │  carbs/protein/fat/fiber/calories/nutrition_source
      │  for the estimated serving size
      ▼
MealResult                         ── response envelope (backend/app/schemas/meal.py)
      │
      ▼
Flutter (MealResult model)         ── lib/models/meal_result.dart
```

## Architectural principle

Recognition and nutrition are decoupled:

- The **recognition model** (initially Gemini Vision, later our team's ML
  model) identifies the food and estimates the serving size. It produces
  `food_id`, `food_name`, `recognition_confidence`, and
  `estimated_serving_size_g`.
- The **nutrition database** (PostgreSQL, e.g. INDB) is the sole authority
  for nutrition values (`carbs_g`, `protein_g`, `fat_g`, `fiber_g`,
  `calories`, `nutrition_source`).

Gemini/ML must never be treated as authoritative for carbohydrates, protein,
fat, calories, or fiber. The nutrition layer stays independent of whichever
recognition model is in use.

## Stages

1. **Flutter (Android)** — user uploads an image. The client sends a
   `multipart/form-data` request to `POST /api/v1/food/analyze`.
   Contract: `docs/api-contract.md`.
2. **FastAPI** — validates the request, delegates to the recognition layer,
   and returns a normalized response. Routing lives in `backend/app/api`;
   response schemas in `backend/app/schemas/meal.py`.
3. **Food Recognition** — initially Gemini Vision, later our own ML model.
   Returns candidate food labels with confidence scores; it never supplies
   nutrition values.
4. **Food Normalization** — resolves the free-text label to a canonical food
   entry (`food_id`) and estimates the serving size. May use fuzzy matching,
   aliases, and locale-specific databases.
5. **Nutrition Database** — PostgreSQL provides the nutrition facts (source
   e.g. `INDB`) for the estimated serving size, independent of the
   recognition model.
6. **MealResult** — the backend assembles the response envelope
   (`success`, `data`, `error`) from the recognition result and the nutrition
   values.
7. **Flutter** — deserializes `data` into `MealResult`
   (`lib/models/meal_result.dart`) via `MealService`
   (`lib/services/meal_service.dart`).

Failures at any stage are returned with the standard error envelope and one
of the codes in `docs/failure-cases.md`.