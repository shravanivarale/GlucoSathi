"""Reusable inspection of an INDB ``.xlsx`` workbook (read-only).

``inspect_dataset`` does not modify the file. It reports the stats needed to
validate import readiness of the dataset:
row/column counts, duplicates, nulls, ``food_code``/``food_name`` uniqueness,
coverage of the required per-100g nutrition fields, and coverage of the
reference-serving fields.
"""

from pathlib import Path
from typing import Any

from .constants import REQUIRED_NUTRITION_COLUMNS, REQUIRED_SERVING_COLUMNS, SERVING_NAME_COLUMN


def inspect_dataset(path: str | Path) -> dict[str, Any]:
    """Return an inspection report for the given workbook."""
    import pandas as pd

    path = Path(path)
    xl = pd.ExcelFile(path)
    report: dict[str, Any] = {"path": str(path), "sheets": {}}
    for sheet in xl.sheet_names:
        df = xl.parse(sheet)
        report["sheets"][sheet] = _inspect_frame(df)
    return report


def _inspect_frame(df: Any) -> dict[str, Any]:
    rows, cols = df.shape
    required_present = [c for c in REQUIRED_NUTRITION_COLUMNS if c in df.columns]
    serving_name_present = SERVING_NAME_COLUMN in df.columns
    required_serving_present = [
        c for c in REQUIRED_SERVING_COLUMNS if c in df.columns
    ]

    def non_null_ratio(columns: list[str]) -> float:
        if not columns:
            return 0.0
        return float(df[columns].notna().all(axis=1).mean())

    return {
        "rows": rows,
        "columns": cols,
        "column_names": list(df.columns),
        "dtypes": {col: str(dt) for col, dt in df.dtypes.items()},
        "duplicated_rows": int(df.duplicated().sum()),
        "null_counts": {col: int(df[col].isna().sum()) for col in df.columns},
        "unique_food_code": (
            int(df["food_code"].nunique()) if "food_code" in df.columns else None
        ),
        "unique_food_name": (
            int(df["food_name"].nunique()) if "food_name" in df.columns else None
        ),
        "required_nutrition_coverage": non_null_ratio(required_present),
        "serving_name_coverage": (
            non_null_ratio([SERVING_NAME_COLUMN]) if serving_name_present else 0.0
        ),
        "serving_coverage": non_null_ratio(required_serving_present),
    }


def format_report(report: dict[str, Any]) -> str:
    """Render an inspection report as human-readable text."""
    lines = [f"Workbook: {report['path']}"]
    for sheet, info in report["sheets"].items():
        lines += [
            f"--- Sheet: {sheet} ---",
            f"  shape: {info['rows']} rows x {info['columns']} cols",
            f"  duplicated rows: {info['duplicated_rows']}",
            f"  unique food_code: {info['unique_food_code']}",
            f"  unique food_name: {info['unique_food_name']}",
            f"  required per-100g nutrition coverage: "
            f"{info['required_nutrition_coverage']:.1%}",
            f"  serving-name coverage: {info['serving_name_coverage']:.1%}",
            f"  serving-value coverage: {info['serving_coverage']:.1%}",
            "  nulls in required fields:",
            *[
                f"    {col}: {count}"
                for col, count in info["null_counts"].items()
                if col in REQUIRED_NUTRITION_COLUMNS
                or col in REQUIRED_SERVING_COLUMNS
                or col == SERVING_NAME_COLUMN
            ],
        ]
    return "\n".join(lines)