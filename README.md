<div align="center">

# 🩸 GlucoSathi

**AI-powered meal recognition and glucose-risk prediction for Indian diabetes management**

Built for **Innovate4Impact 2026** · PS 2632 — *AI-Powered Hypoglycemia Prediction & Carb-Counting Tool for Indian T1D Diets*

[![Flutter](https://img.shields.io/badge/Flutter-3.12%2B-02569B?logo=flutter&logoColor=white)](https://flutter.dev)
[![FastAPI](https://img.shields.io/badge/FastAPI-0.110%2B-009688?logo=fastapi&logoColor=white)](https://fastapi.tiangolo.com)
[![Python](https://img.shields.io/badge/Python-3.12.3-3776AB?logo=python&logoColor=white)](https://www.python.org)


[Features](#-features) · [Architecture](#-architecture) · [Quick Start](#-quick-start) · [API](#-api-reference) · [Roadmap](#-roadmap) · [Team](#-team)

</div>




## 📖 Overview

People with Type 1 Diabetes (T1D) need to match every carbohydrate they eat with an insulin dose. Get either side of that equation wrong — the carb estimate or the insulin timing — and the result can be a dangerous swing into hypoglycemia (low blood sugar).

Existing Indian diabetes apps (BeatO, Sugar.fit, Fitterfly) are built around **Type 2 diabetes lifestyle/reversal coaching.** None of them offer a bolus (insulin-dose) calculator, an Indian-dish carb database, or a genuine hypoglycemia predictor. **That gap is GlucoSathi's whole reason for existing.**

GlucoSathi:

1. **Recognizes food** from a meal photo using Gemini Vision
2. **Matches** the recognized dish against the **Indian Nutrient Databank (INDB)**
3. **Returns honest, per-100g nutrition values** — never a fabricated guess
4. **Predicts glucose trends** 30/60 minutes out using an ONNX ML model trained on CGM-style data
5. **Tracks glucose and insulin-on-board** to power a live Low / Medium / High risk banner

---

## ✨ Features

| Feature | Status |
|---|---|
| 📸 Photo-based food recognition (Gemini Vision) | ✅ MVP |
| 🍛 INDB-backed nutrition lookup (per-100g, never fabricated) | ✅ MVP |
| 🔎 Exact / substring / fuzzy food-name matching (≥ 0.75 confidence) | ✅ MVP |
| 📊 30 / 60-minute glucose prediction (ONNX inference) | ✅ MVP |
| 🚦 Color-coded risk banner (Low / Medium / High) | ✅ MVP |
| 🔐 Firebase email/password authentication | ✅ MVP |
| ⚡ Quick-log bar for frequent foods | ✅ MVP |
| 📷 Manual entry for cooked dishes & packaged items | ✅ MVP |
| 🇮🇳 NPH/Regular insulin pharmacokinetics (not just rapid-acting analogues) | 🧪 Stage 2 |
| 📈 Clarke Error Grid model validation | 🔜 Stage 2 |
| 🍽️ CV-based portion-size estimation from photos | 🔜 Stage 2 |
| 🩺 CGM device integration (Dexcom / FreeStyle) | 🔜 Roadmap |

---

## 🏗 Architecture

```
Flutter (Android/iOS/Web/Desktop)
        │ POST /api/v1/foods/analyze (multipart: image)
        ▼
FastAPI Backend (app.main)
        │ Routing via app/api/foods.py
        ▼
Image Validation  →  magic-byte sniffing, JPEG/PNG, 10MB max
        ▼
Food Recognition (Gemini Vision)  →  food names + confidence (NO nutrition)
        ▼
Food Normalization  →  exact → substring → fuzzy (≥ 0.75) match to INDB food_id
        ▼
NutritionRepository (SQLite, seeded from INDB)  →  per-100g values
        ▼
Nutrition Calculator  →  scale per-100g to estimated serving size
        ▼
Response Assembly  →  FoodAnalyzeResponse (foods + total_nutrition)
        ▼
Flutter Client  →  parse, display, log meal, trigger glucose prediction
```

### Core design principles

- **Decoupled recognition & nutrition** — Gemini Vision identifies *what* food it is; INDB is the sole authority on *what's in it*. Swapping either layer never touches the other.
- **Dependency inversion** — `FoodRecognizer` and `NutritionRepository` are interfaces; concrete implementations (`GeminiVisionRecognizer`, `SQLiteNutritionRepository`) are swap points in `app/api/dependencies.py`.
- **Never fabricate nutrition values** — if no INDB match clears the 0.75 fuzzy-confidence bar, the app returns `matched: false`, not a guess.
- **Repository seam for storage independence** — SQLite today, PostgreSQL/Mongo tomorrow, with zero changes to business logic.

---

## 🧰 Tech stack

**Backend**

| Component | Technology | Version |
|---|---|---|
| Runtime | Python | 3.12.3 |
| Framework | FastAPI | ≥ 0.110 |
| ASGI Server | Uvicorn | ≥ 0.29 |
| AI Recognition | Google Gemini Vision (`google-genai`) | ≥ 1.0 |
| Database | SQLite3 | built-in |
| ML Inference | ONNX Runtime | ≥ 1.20.0 |
| Data Processing | Pandas + OpenPyXL | ≥ 2.0 / ≥ 3.1 |
| Validation | Pydantic | ≥ 2.0 |
| Testing | Pytest | ≥ 7.0 |

**Frontend**

| Component | Technology | Version |
|---|---|---|
| Framework | Flutter | SDK ≥ 3.12.2 |
| Language | Dart | 3.12.2+ |
| Auth | Firebase Auth | ≥ 6.5.7 |
| Image capture | image_picker | ≥ 1.1.2 |
| Networking | package:http | ≥ 1.6.0 |

**Platforms:** Android (primary), iOS, Web, Windows, macOS, Linux

---

## 📁 Repository structure

```
glucosaathi/
├── backend/                     # Python FastAPI backend
│   ├── app/
│   │   ├── main.py              # FastAPI entry point
│   │   ├── api/                 # Routers: foods.py, glucose.py, errors.py, images.py
│   │   ├── services/            # gemini_service, food_analyzer, nutrition_calculator,
│   │   │                        # glucose_predictor, glucose_preprocessor
│   │   ├── repositories/        # NutritionRepository interface
│   │   ├── database/            # SQLiteNutritionRepository
│   │   ├── models/ & schemas/   # Domain models + Pydantic request/response schemas
│   │   └── seed/                # INDB Excel → SQLite importer
│   ├── data/                    # Anuvaad_INDB_2024.11.xlsx (seed input)
│   ├── models/                  # glucose_model.onnx + scalers.json
│   └── tests/                   # Pytest suite
├── lib/                         # Flutter app root
│   ├── auth/                    # Firebase auth service + login screen
│   ├── screens/                 # home/, profile/
│   ├── services/                # meal_service, glucose_api_service
│   ├── core/                    # network, constants, errors, utils
│   ├── models/                  # FoodAnalysis, LoggedMealEntry, GlucosePrediction, ...
│   └── widgets/                 # GlucoseStatusCard, RiskPredictionBanner, ...
├── docs/                        # api.md, api-contract.md, architecture.md, failure-cases.md
├── .env.example
└── README.md
```

---

## 🚀 Quick start

### Prerequisites

- **Python 3.12** (tested on 3.12.3)
- **Flutter SDK ≥ 3.12.2**
- **Git**
- **Gemini API key** — get one at [aistudio.google.com/apikey](https://aistudio.google.com/apikey) (required only for the food-recognition endpoints)

### 1. Clone the repo

```bash
git clone https://github.com/shravanivarale/GlucoSathi.git
cd GlucoSathi
```

### 2. Backend setup

```bash
cd backend
python -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

Copy the env template (must live at repo root, not `backend/.env`):

```bash
cp ../.env.example ../.env
# then edit .env and set GEMINI_API_KEY
```

Seed the nutrition database from INDB:

```bash
python -m app.seed.seed
```

Start the API server:

```bash
uvicorn app.main:app --reload
```

- API: `http://localhost:8000`
- Swagger docs: `http://localhost:8000/docs`
- Health check: `GET http://localhost:8000/health`

### 3. Frontend setup

```bash
# From repo root
flutter pub get

# Android emulator (backend reachable at 10.0.2.2)
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000

# Physical device (use your machine's LAN IP)
flutter run --dart-define=API_BASE_URL=http://192.168.1.5:8000
```

### 4. Run tests

```bash
# Backend
cd backend && python -m pytest -v

# Frontend
flutter test
```

---

## 🔌 API reference

Base URL (dev): `http://localhost:8000` · Base URL (prod): `https://glucosaathi-backend.onrender.com`
All endpoints are versioned under `/api/v1` except the health check.

| Method | Path | Purpose | Auth |
|---|---|---|---|
| `GET` | `/health` | Service health check | None |
| `POST` | `/api/v1/foods/recognize` | Recognize food from an image (name only) | None |
| `POST` | `/api/v1/foods/analyze` | Recognize + INDB nutrition lookup | None |
| `POST` | `/api/v1/glucose/predict` | Predict glucose 30/60 min ahead | None |

<details>
<summary><strong>POST /api/v1/foods/analyze</strong></summary>

**Request:** `multipart/form-data`, field `image` (JPEG/PNG, ≤ 10 MB)

**Response — matched:**
```json
{
  "foods": [
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
  ],
  "total_nutrition": { "carb_g": 35.048, "protein_g": 6.085, "fat_g": 14.138, "fibre_g": 3.716, "energy_kcal": 294.526 }
}
```

**Response — no reliable match:**
```json
{
  "foods": [{ "recognized_food": "Rajma Chawal", "matched": false, "message": "Food not found in nutrition database" }],
  "total_nutrition": null
}
```
</details>

<details>
<summary><strong>POST /api/v1/glucose/predict</strong></summary>

**Request:**
```json
{
  "readings": [
    { "cbg": 124.0, "basal": 0.0, "hr": 0.0, "gsr": 0.0, "carbInput": 45.0, "bolus": 2.0, "timestamp": "2026-09-10T12:00:00Z" }
    /* ...24 readings total, 5-min intervals, 2 hours of history... */
  ]
}
```

**Response:**
```json
{ "prediction_30_min": 112.5, "prediction_60_min": 108.3 }
```
</details>

<details>
<summary><strong>Error envelope</strong></summary>

All errors share one shape:
```json
{ "error": { "code": "ERROR_CODE", "message": "Human-readable message" } }
```

| Code | HTTP | Meaning |
|---|---|---|
| `INVALID_IMAGE` | 400 | No image, corrupt, or unsupported format |
| `IMAGE_TOO_LARGE` | 413 | Image exceeds 10 MB |
| `FOOD_NOT_RECOGNIZED` | 422 | No food identifiable in image |
| `LOW_CONFIDENCE` | 422 | Recognized but below confidence threshold |
| `FOOD_NOT_FOUND` | 404 | Recognized food isn't in INDB |
| `NUTRITION_DATA_NOT_FOUND` | 404 | Food exists but nutrition values missing |
| `ANALYSIS_FAILED` | 502 | Recognition service error (Gemini, network, key) |
| `INTERNAL_ERROR` | 500 | Unexpected backend error |

</details>

Full contract: [`docs/api.md`](docs/api.md) · [`docs/api-contract.md`](docs/api-contract.md)

---

## 🧠 The glucose prediction model

- ONNX Runtime inference over **24 readings × 12 features** (5-minute intervals, 2 hours of history)
- Features include current glucose, rate-of-change, **insulin-on-board split by type** (analogue / regular / NPH), carbs-on-board, smoothed heart rate & GSR, and cyclical time encoding
- Outputs a 30-minute and 60-minute glucose forecast, feeding the color-coded risk banner in the app

This insulin-type split matters specifically for Indian T1D care: cheaper **Human Regular / NPH** insulins (common in government and low-cost pharmacies) have much broader, less predictable peaks than the rapid-acting analogues (Humalog/Novorapid) that most Western diabetes apps assume — a mid-day NPH dose can still be near its peak at 9–11 PM, making a heavy late dinner a classic nocturnal-hypoglycemia setup that generic apps don't model.

---


## 🧪 Testing

```bash
# Backend — from backend/
python -m pytest             # all tests
python -m pytest -v          # verbose
python -m pytest --cov=app   # with coverage

# Frontend — from repo root
flutter test
flutter test --coverage
```

---

## ☁️ Deployment

**Backend (Render):** connect the GitHub repo, set build command `cd backend && pip install -r requirements.txt && python -m app.seed.seed`, start command `cd backend && uvicorn app.main:app --host 0.0.0.0 --port 8000`, and set `GEMINI_API_KEY` in environment variables.

**Frontend:**
```bash
flutter build apk --release     # Android → Play Store
flutter build ios --release     # iOS → App Store via Xcode
flutter build web --release     # Web → Firebase Hosting / CDN
```

---

## 🎯 Target users

- **T1D families** — parents of pediatric T1D patients (highest urgency, highest willingness-to-pay)
- **Pediatric endocrinologists & diabetes educators** — clinical-credibility and B2B channel
- **T1D patient communities & support groups** — early adopters, low-cost acquisition

T1D is a much smaller population than T2D in India but far higher-stakes per user — a deliberate niche instead of competing head-on with T2D-focused apps.




<div align="center">
<sub>GlucoSathi outputs are decision support only. Always confirm insulin dosing with your care team.</sub>
</div>
