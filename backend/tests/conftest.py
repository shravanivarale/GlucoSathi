"""Shared fixtures: real INDB import + seeded SQLite repositories.

Tests in ``test_seed_import.py``, ``test_sqlite_repository.py`` and
``test_indb_lookup.py`` exercise the real dataset mapping. If the workbook is
not present the tests are skipped rather than failed.
"""

import pytest

from app.database.sqlite import SQLiteNutritionRepository
from app.seed.constants import DEFAULT_XLSX_PATH
from app.seed.importer import import_dataset
from app.seed.seed import seed_database


@pytest.fixture(scope="session")
def indb_dataset():
    if not DEFAULT_XLSX_PATH.exists():
        pytest.skip(f"INDB dataset not found: {DEFAULT_XLSX_PATH}")
    return import_dataset(DEFAULT_XLSX_PATH)


@pytest.fixture()
def seeded_db_path(tmp_path, indb_dataset):
    db_path = tmp_path / "glucosaathi.db"
    seed_database(indb_dataset, db_path)
    return db_path


@pytest.fixture()
def indb_repo(seeded_db_path):
    return SQLiteNutritionRepository(seeded_db_path)