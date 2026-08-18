# API Reference

GlucoSaathi backend, implemented with FastAPI. Base URL in local dev:
**http://localhost:8000**. Interactive docs: `/docs`.

All endpoints are versioned under `/api/v1` (except the root health check).

| Method | Path                       | Purpose                                                        |
|--------|----------------------------|----------------------------------------------------------------|
| GET    | `/health`                  | Service health check.                                          |
| POST   | `/api/v1/foods/recognize`  | Recognize the food in an uploaded image (name only).           |
| POST   | `/api/v1/foods/analyze`    | Full workflow: recognize the food, then return INDB nutrition. |

## GET /health

Service health check. No authentication.

`HTTP 200 OK`

```json
{ "status": "ok" }
```

## POST /api/v1/foods/recognize

Recognize the food in an uploaded image and return the canonical food name
(nutrition is not consulted).

**Request** — `multipart/form-data`

| Field | Type   | Required | Description         |
|-------|--------|----------|---------------------|
| image | `file` | yes      | JPEG/PNG image file |

**Success — `HTTP 200 OK`**

```json
{ "recognized_food": "Rajma Chawal" }
```

**Errors**

- `422` — file missing or `Content-Type: multipart/form-data` not used.
- `415` — declared MIME type is not JPEG/PNG, or the magic bytes don't match.
- `413` — image larger than 10 MB.
- `502` — recognition service failed (`ANALYSIS_FAILED`), e.g. Gemini error or missing `GEMINI_API_KEY`.

## POST /api/v1/foods/analyze

Recognize the food, then match it against the INDB nutrition database.

**Request** — identical to `/recognize`.

**Success (matched) — `HTTP 200 OK`**

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

**Success (no reliable match) — `HTTP 200 OK`**

```json
{
  "recognized_food": "Rajma Chawal",
  "matched": false,
  "message": "Food not found in nutrition database"
}
```

**Errors** — same as `/recognize`.

## Shared behaviour

- Both POST endpoints accept raw `image` file bytes via `multipart/form-data`.
  Images are validated by declared MIME type **and** magic-byte sniffing
  (JPEG `FF D8 FF`, PNG `89 50 4E 47 0D 0A 1A 0A`), max 10 MB, and are
  processed in memory — never stored on disk.
- Nutrition values always come from the INDB-derived database, never from the
  recognition model, and are never fabricated when no reliable match exists.
- Errors are returned as `ApiException` envelopes; see
  [`docs/failure-cases.md`](./failure-cases.md) for the full code/status list
  and [`docs/api-contract.md`](./api-contract.md) for the detailed client
  contract.