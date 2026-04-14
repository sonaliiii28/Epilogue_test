"""Generate `assets/data/hospice_medications.json` from an Excel file.

Intended workflow (offline app, rare updates):
1) Replace/update the Excel source file.
2) Run this script to regenerate the JSON asset.
3) Commit the updated JSON asset.

The Flutter app loads this JSON at runtime (offline) via `rootBundle`.

Example:
  python tools/generate_hospice_medications_json.py \
    --input Hospice_Medications_Complete_Dosages.xlsx \
    --output assets/data/hospice_medications.json
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Dict, Iterable, List, Optional


def _norm(s: Any) -> str:
    return str(s).strip() if s is not None else ""


def _pick_column(cols: Iterable[str], candidates: List[str]) -> Optional[str]:
    lowered = {c.lower().strip(): c for c in cols}
    for cand in candidates:
        key = cand.lower().strip()
        if key in lowered:
            return lowered[key]
    return None


def _first_sheet(df_map: Dict[str, "pd.DataFrame"]) -> "pd.DataFrame":
    # Prefer a sheet that looks like the meds table.
    preferred_names = [
        "medications",
        "hospice medications",
        "hospice_medications",
        "sheet1",
    ]
    for name in preferred_names:
        for actual in df_map.keys():
            if actual.lower().strip() == name:
                return df_map[actual]
    # Fallback: first sheet.
    return next(iter(df_map.values()))


def _detect_header_row(raw_df: "pd.DataFrame", *, max_rows: int = 50) -> int:
    """Find the row index that contains the real column headers.

    Some spreadsheets include a title row and/or description rows above the
    actual header row. This function scans for a row containing 'Medication'
    and at least one other expected header.
    """

    expected_any = {
        "brand",
        "brand name(s)",
        "available forms",
        "available dosage strengths",
        "clinical notes",
        "route",
        "route/form",
    }
    for i in range(min(max_rows, len(raw_df))):
        row = raw_df.iloc[i].astype(str).str.strip().str.lower().tolist()
        if "medication" in row:
            hits = sum(1 for cell in row if cell in expected_any)
            if hits >= 1:
                return i
    return 0


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", required=True, help="Path to .xlsx file")
    parser.add_argument(
        "--output",
        default="assets/data/hospice_medications.json",
        help="Output JSON path",
    )
    parser.add_argument(
        "--sheet",
        default=None,
        help="Optional sheet name; default is auto-detected",
    )
    args = parser.parse_args()

    input_path = Path(args.input)
    output_path = Path(args.output)

    if not input_path.exists():
        raise SystemExit(f"Input not found: {input_path}")

    try:
        import pandas as pd  # type: ignore
    except Exception as e:  # pragma: no cover
        raise SystemExit(
            "pandas is required. Install with: pip install pandas openpyxl\n"
            f"Original error: {e}"
        )

    # Read all sheets (raw) so we can auto-detect the data sheet and header row.
    df_map = pd.read_excel(input_path, sheet_name=None, header=None, dtype=str)
    if not df_map:
        raise SystemExit("No sheets found in Excel file")

    if args.sheet:
        if args.sheet not in df_map:
            raise SystemExit(
                f"Sheet not found: {args.sheet}. Available: {list(df_map.keys())}"
            )
        selected_sheet_name = args.sheet
        raw_df = df_map[selected_sheet_name]
    else:
        raw_df = _first_sheet(df_map)
        selected_sheet_name = None
        for k, v in df_map.items():
            if v is raw_df:
                selected_sheet_name = k
                break
        if selected_sheet_name is None:
            selected_sheet_name = next(iter(df_map.keys()))

    raw_df_filled = raw_df.fillna("")
    header_row = _detect_header_row(raw_df_filled)

    # Re-read the selected sheet using the detected header row.
    # header=N uses row N for columns and starts data at N+1.
    df = pd.read_excel(
        input_path,
        sheet_name=selected_sheet_name,
        header=header_row,
        dtype=str,
    ).fillna("")

    cols = list(df.columns)

    # Flexible column matching: update candidates if your spreadsheet uses different headers.
    name_col = _pick_column(
        cols,
        [
            "name",
            "generic",
            "generic name",
            "medication",
            "medication name",
        ],
    )
    brand_col = _pick_column(cols, ["brand", "brand name", "brand name(s)", "brands"])
    primary_use_col = _pick_column(
        cols,
        [
            "primaryuse",
            "primary use",
            "use",
            "indication",
            "common use",
        ],
    )
    route_col = _pick_column(
        cols,
        [
            "route",
            "route/form",
            "route of administration",
            "form",
            "routes",
            "available forms",
        ],
    )
    dose_unit_col = _pick_column(
        cols,
        [
            "doseunit",
            "dose unit",
            "unit",
            "units",
            "dose units",
            "dosage units",
            "available dosage strengths",
        ],
    )

    if not name_col:
        raise SystemExit(
            "Could not find a medication name column. "
            f"Columns found: {cols}"
        )

    rows: List[Dict[str, str]] = []
    for _, r in df.iterrows():
        name = _norm(r.get(name_col, ""))
        if not name:
            continue

        rows.append(
            {
                "name": name,
                "brand": _norm(r.get(brand_col, "")) if brand_col else "",
                "primaryUse": _norm(r.get(primary_use_col, "")) if primary_use_col else "",
                "route": _norm(r.get(route_col, "")) if route_col else "",
                "doseUnit": _norm(r.get(dose_unit_col, "")) if dose_unit_col else "",
            }
        )

    # Stable order helps diffs.
    rows.sort(key=lambda x: x["name"].lower())

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(json.dumps(rows, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    print(f"Wrote {len(rows)} medications -> {output_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
