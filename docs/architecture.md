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
      │  food label/name + recognition_confidence
      │  + estimated_serving_size_g   (recognition & portion — no nutrition)
      ▼
Food Normalization                 ── label → canonical food entry (food_id)
      │
      ▼
NutritionRepository                ── data-access abstraction (backend/app/repositories)
      │  get_food / get_nutrition (per-100g values)
      ▼
Nutrition Database                ── logical store on a per-100g basis;
      │                               SQLite seeded from the INDB dataset
      │  carbs/protein/fat/fiber/calories per 100 g
      ▼
Serving-size calculation           ── per-100g × estimated_serving_size_g / 100
      │  nutrition values for the estimated serving size
      ▼
MealResult                         ── response envelope (backend/app/schemas/meal.py)
      │
      ▼
Flutter (MealResult model)         ── lib/models/meal_result.dart
```

## Architectural principle

Recognition and nutrition are decoupled:

- The **recognition model** (initially Gemini Vision, later our team's ML
  model) identifies the food and estimates the serving size. It produces only
  a food label/`food_name`, `recognition_confidence`, and
  `estimated_serving_size_g` — never nutrition values. `food_id` is the
  canonical nutrition-database identifier assigned when the label is
  normalized against the nutrition data, not by the model itself.
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
   Returns candidate food labels with confidence scores and a serving-size
   estimate; it never supplies nutrition values. A canonical `food_id` is
   assigned by normalization, not by the model.
4. **Food Normalization** — resolves the free-text label to a canonical food
   entry (`food_id`); the serving-size estimate comes from the recognition
   stage. May use fuzzy matching, aliases, and locale-specific databases.
5. **Nutrition Database / Repository** — the nutrition layer stores facts on a
   per-100g basis behind the `NutritionRepository` abstraction at
   `backend/app/repositories/`. A pure calculation scales the per-100g values
   by the estimated serving size (`nutrition_per_100g × serving_size_g / 100`,
   see `backend/app/services/nutrition_calculator.py`). This layer is
   independent of the recognition model. The physical database is SQLite
   (`backend/app/database/sqlite.py`), seeded from the INDB dataset by
   `backend/app/seed/seed.py`, and exposed through
   `SQLiteNutritionRepository`. `InMemoryNutritionRepository` remains for
   tests (synthetic fixtures only).
6. **MealResult** — the backend assembles the response envelope
   (`success`, `data`, `error`) from the recognition result and the nutrition
   values.
7. **Flutter** — deserializes `data` into `MealResult`
   (`lib/models/meal_result.dart`) via `MealService`
   (`lib/services/meal_service.dart`).

Failures at any stage are returned with the standard error envelope and one
of the codes in `docs/failure-cases.md`.

## Nutrition data layer

Logical data design, independent of the recognition model, of the physical
database, and of the actual dataset (`backend/app/models/food.py`). These are
schema contracts; no production food/nutrition records are populated yet.

- **Food** — `food_id` (stable identifier; names may change or have aliases),
  `food_name`, `category`, `nutrition_source`, optional `reference_serving_g`
  (populated only if the chosen dataset provides it).
- **FoodNutrition** — per-100g values: `carbs_g_per_100g`,
  `protein_g_per_100g`, `fat_g_per_100g`, `fiber_g_per_100g`,
  `calories_per_100g`, `nutrition_source`. Values come from the dataset, never
  from the recognition model.
- **Aliases** — multiple food names may map to a single stable `food_id`. No
  separate alias table; a lookup is enough for the MVP.
- **Serving-size calculation** — `nutrition_for_serving =
  nutrition_per_100g × estimated_serving_size_g / 100`
  (`backend/app/services/nutrition_calculator.py`), producing
  `ServingNutrition` which feeds the `MealResult` contract.
- **Repository** — `NutritionRepository` exposes
  `get_food(food_id)` / `get_nutrition(food_id)`. Recognition code and API
  endpoints depend on this interface, never on a concrete storage
  implementation. Missing foods / values raise `FoodNotFoundError` /
  `NutritionDataNotFoundError`, matching the `FOOD_NOT_FOUND` /
  `NUTRITION_DATA_NOT_FOUND` failure codes. `SQLiteNutritionRepository`
  (seeded from INDB) is the production implementation;
  `InMemoryNutritionRepository` is retained as a synthetic test fixture
  backend and ships empty.

## Dataset import contract (implemented)

The INDB dataset (`data/Anuvaad_INDB_2024.11.xlsx`) is imported by
`backend/app/seed`:

```
External Dataset (INDB)
      ↓  app/seed/importer.py (field mapping, category, aliases)
Normalized Food + FoodNutrition records (per 100 g)
      ↓
app/seed/seed.py  (idempotent wipe-and-reload; never duplicates)
      ↓
SQLite Nutrition Database (backend/app/database/sqlite.py)
```

The importer maps the dataset's columns onto the normalized records defined
above, producing at minimum:

```
food_id
food_name
nutrition_source
carbs_g_per_100g
protein_g_per_100g
fat_g_per_100g
fiber_g_per_100g
calories_per_100g
```

plus INDB's named reference serving (per-serving values) in the `food_servings`
table and derived name aliases in `food_alias` for the Food Normalization
stage.