"""Repeatable INDB import/seed CLI.

Populates the SQLite nutrition database from the INDB workbook. The import
is idempotent: within a single transaction all INDB-derived rows are removed
and re-inserted (keyed on ``food_id``), so re-running never creates duplicate
records.

Usage
-----
    python -m app.seed.seed [--xlsx <path>] [--db <path>] [--inspect] [--verbose]

    --inspect  print an inspection report of the workbook instead of seeding
    --verbose  print each food's mapped record (for small test fixtures)
"""

import argparse
import sys
from pathlib import Path

from app.database.records import ServingRecord
from app.database.sqlite import (
    SQLiteNutritionRepository,
    connect,
    init_schema,
)
from app.models.food import FoodNutrition

from .constants import DEFAULT_XLSX_PATH
from .importer import ImportedDataset, import_dataset
from .inspect import format_report, inspect_dataset

DEFAULT_DB_PATH = Path(__file__).resolve().parents[2] / "data" / "glucosaathi.db"


def seed_database(
    dataset: ImportedDataset,
    db_path: str | Path,
    verbose: bool = False,
) -> dict[str, int]:
    """Write the normalized dataset into the SQLite database (idempotent).

    Returns the number of rows inserted per table.
    """
    conn = connect(db_path)
    init_schema(conn)
    try:
        conn.execute("PRAGMA foreign_keys = OFF")  # order-independent reload
        with conn:
            _delete_all(conn)
            foods = _insert_foods(conn, dataset)
            nutrition = _insert_nutrition(conn, dataset.nutrition)
            aliases = _insert_aliases(conn, dataset.aliases)
            servings = _insert_servings(conn, dataset.servings)
        conn.execute("PRAGMA foreign_keys = ON")
    finally:
        conn.close()

    inserted = {
        "foods": foods,
        "nutrition": nutrition,
        "aliases": aliases,
        "servings": servings,
    }
    if verbose:
        _print_records(dataset)
    return inserted


def _delete_all(conn) -> None:
    for table in (
        "food_servings",
        "food_alias",
        "food_nutrition",
        "foods",
    ):
        conn.execute(f"DELETE FROM {table}")


def _insert_foods(conn, dataset: ImportedDataset) -> int:
    conn.executemany(
        "INSERT INTO foods"
        " (food_id, food_name, category, nutrition_source,"
        "  dataset_source, reference_serving_g)"
        " VALUES (?, ?, ?, ?, ?, NULL)",
        [
            (
                f.food_id,
                f.food_name,
                f.category,
                f.nutrition_source,
                dataset.dataset_sources.get(f.food_id),
            )
            for f in dataset.foods
        ],
    )
    return len(dataset.foods)


def _insert_nutrition(conn, nutrition: list[FoodNutrition]) -> int:
    conn.executemany(
        "INSERT INTO food_nutrition"
        " (food_id, nutrition_source, carbs_g_per_100g, protein_g_per_100g,"
        "  fat_g_per_100g, fiber_g_per_100g, calories_per_100g)"
        " VALUES (?, ?, ?, ?, ?, ?, ?)",
        [
            (
                n.food_id,
                n.nutrition_source,
                n.carbs_g_per_100g,
                n.protein_g_per_100g,
                n.fat_g_per_100g,
                n.fiber_g_per_100g,
                n.calories_per_100g,
            )
            for n in nutrition
        ],
    )
    return len(nutrition)


def _insert_aliases(conn, aliases: dict[str, str]) -> int:
    conn.executemany(
        "INSERT INTO food_alias (alias, food_id) VALUES (?, ?)",
        list(aliases.items()),
    )
    return len(aliases)


def _insert_servings(conn, servings: list[ServingRecord]) -> int:
    conn.executemany(
        "INSERT INTO food_servings"
        " (food_id, serving_name, serving_size_g, carbs_g, protein_g,"
        "  fat_g, fiber_g, calories)"
        " VALUES (?, ?, NULL, ?, ?, ?, ?, ?)",
        [
            (s.food_id, s.serving_name, s.carbs_g, s.protein_g, s.fat_g,
             s.fiber_g, s.calories)
            for s in servings
        ],
    )
    return len(servings)


def _print_records(dataset) -> None:
    for food in dataset.foods:
        print(
            f"{food.food_id}\t{food.food_name}\t{food.category}\t"
            f"{food.nutrition_source}"
        )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Inspect and seed the INDB nutrition database."
    )
    parser.add_argument(
        "--xlsx",
        type=Path,
        default=DEFAULT_XLSX_PATH,
        help="Path to the INDB workbook (default: repo data dir).",
    )
    parser.add_argument(
        "--db",
        type=Path,
        default=DEFAULT_DB_PATH,
        help="Path to the SQLite database file (default: backend/data).",
    )
    parser.add_argument("--inspect", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args(argv)

    if args.inspect:
        print(format_report(inspect_dataset(args.xlsx)))
        return 0

    if not args.xlsx.exists():
        print(
            f"Dataset not found: {args.xlsx}",
            file=sys.stderr,
        )
        return 1

    dataset = import_dataset(args.xlsx)
    inserted = seed_database(dataset, args.db, verbose=args.verbose)

    repo = SQLiteNutritionRepository(args.db)
    print(
        f"Seed complete. Inserted {inserted['foods']} foods, "
        f"{inserted['nutrition']} nutrition rows, "
        f"{inserted['aliases']} aliases, "
        f"{inserted['servings']} serving records into {args.db}"
    )
    print("Database rows after seed:", repo.counts())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())