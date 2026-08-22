# GlucoSaathi

Food Image Upload + Food Recognition MVP: a Flutter client that photographs a
meal, a FastAPI backend that recognizes the food with Gemini Vision, and an
INDB-backed (Indian Food Nutrition) lookup that returns honest per-100g
nutrition values.

Repo layout:

- `backend/` — Python 3.12 FastAPI service (recognition + nutrition lookup).
- `lib/`, `android/`, `ios/`, `linux/`, `macos/`, `web/`, `windows/` — the Flutter app.
- `data/Anuvaad_INDB_2024.11.xlsx` — the committed INDB dataset workbook (seed input).
- `docs/` — [`api.md`](docs/api.md) (endpoint reference), [`api-contract.md`](docs/api-contract.md) (detailed client contract), [`architecture.md`](docs/architecture.md), [`failure-cases.md`](docs/failure-cases.md).

## Prerequisites

- Python **3.12** (developed and tested on 3.12.3).
- A Gemini API key (only needed for the food-recognition endpoints; the rest of the API runs without it.)
- Flutter SDK if you also run the mobile client.

## Backend setup

Run all backend commands from `backend/`.

1. **Clone** the repository:

   ```sh
   git clone <repo-url>
   cd glucosaathi/backend
   ```

2. **Create the virtual environment**:

   ```sh
   python -m venv .venv
   ```

3. **Activate it**:

   ```sh
   # Linux/macOS
   source .venv/bin/activate
   # Windows (PowerShell)
   .venv\Scripts\activate
   ```

   (Alternatively, call `.venv/bin/python` instead of activating, e.g. `.venv/bin/python -m pytest`.)

4. **Install requirements**:

   ```sh
   pip install -r requirements.txt
   ```

5. **Configure the Gemini API key**: copy `.env.example` to `.env` (repo root) and
   fill in `GEMINI_API_KEY`. The backend loads `<repo-root>/.env` on startup; the
   file is gitignored and never committed. The recognition endpoints report a
   clear error if the key is missing.

6. **Seed the nutrition database** (already committed, but re-run it after every
   backend pull or dataset change):

   ```sh
   python -m app.seed.seed
   ```

   This populates `backend/data/glucosaathi.db` (gitignored) from the committed
   workbook `data/Anuvaad_INDB_2024.11.xlsx`. The import is idempotent, so
   re-running is safe. To point at a different workbook or DB:

   ```sh
   python -m app.seed.seed --xlsx /path/to/INDB.xlsx --db /path/to/glucosaathi.db
   python -m app.seed.seed --inspect   # preview the workbook without seeding
   ```

7. **Start the server** (from `backend/`):

   ```sh
   uvicorn app.main:app --reload
   ```

   Serves at **http://localhost:8000**. The Android emulator reaches
   it via http://10.0.2.2:8000, which is the Flutter client's default
   (`--dart-define=API_BASE_URL=...` overrides it).

8. **API docs**: FastAPI auto-generates interactive Swagger docs at
   **http://localhost:8000/docs**.

## Tests

```sh
# Backend (from backend/, with the venv active)
python -m pytest

# Flutter (from the repo root)
flutter test
```

## Architecture note: the repository seam

Recognition and nutrition are decoupled. API endpoints and `FoodAnalyzer`
(`backend/app/services/food_analyzer.py`) depend on two interfaces, never on
concrete implementations:

- `FoodRecognizer` (`backend/app/services/gemini_service.py`) — the recognition
  model seam. `GeminiVisionRecognizer` is the current implementation. **To swap
  Gemini for your own ML model, implement `FoodRecognizer` and rewire
  `get_food_recognizer` in `backend/app/api/dependencies.py` only** — the data
  layer is untouched.
- `NutritionRepository` (`backend/app/repositories/base.py`) — the storage seam
  (`get_food`, `get_nutrition`, `find_food_match`). `SQLiteNutritionRepository`
  (`backend/app/database/sqlite.py`) is the current implementation. Swapping the
  store (e.g. PostgreSQL) means implementing `NutritionRepository` and rewiring
  `get_nutrition_repository` in `dependencies.py`.

Endpoint reference: see [`docs/api.md`](docs/api.md).
