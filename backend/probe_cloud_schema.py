"""Probe Supabase Cloud schema vs local SQL.

Two modes:

1) Exact schema diff (recommended):
   - Set DATABASE_URL (Postgres connection string) and run:
       python backend/probe_cloud_schema.py --mode exact

2) Best-effort REST probe (no DB password needed):
   - Set SUPABASE_URL and SUPABASE_KEY (anon or service role) and run:
       python backend/probe_cloud_schema.py --mode rest

Notes:
- The REST probe can be blocked by RLS/privileges; it still detects missing tables/columns
  when PostgREST returns "not found" errors, but it cannot guarantee exact matches.
- The exact mode uses information_schema.columns and will give a precise diff.
"""

from __future__ import annotations

import argparse
import os
import re
import json
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Set, Tuple, Literal

from dotenv import load_dotenv


ROOT = Path(__file__).resolve().parent
load_dotenv(ROOT / ".env")

DOCX_SQL = ROOT / "supabase_docx_schema.sql"
LEGACY_SQL = ROOT / "supabase_schema.sql"
DOCX_CALENDAR_SQL = ROOT / "supabase_cloud_create_calendar_events.sql"


def _extract_dart_define(args: Iterable[str], name: str) -> str:
    prefix = f"--dart-define={name}="
    for a in args:
        if a.startswith(prefix):
            return a[len(prefix) :]
    return ""


def _auto_supabase_from_workspace() -> Tuple[str, str]:
    """Best-effort read of SUPABASE_URL and SUPABASE_ANON_KEY from workspace files."""

    project_root = ROOT.parent
    launch_json = project_root / ".vscode" / "launch.json"
    if launch_json.exists():
        try:
            data = json.loads(launch_json.read_text(encoding="utf-8"))
            configs = data.get("configurations") or []
            for cfg in configs:
                args = cfg.get("args") or []
                url = _extract_dart_define(args, "SUPABASE_URL")
                key = _extract_dart_define(args, "SUPABASE_ANON_KEY")
                if url and key:
                    return url, key
        except Exception:
            pass

    main_dart = project_root / "lib" / "main.dart"
    if main_dart.exists():
        text = main_dart.read_text(encoding="utf-8")
        url = ""
        key = ""

        m1 = re.search(r"defaultValue:\s*'([^']*supabase\\.co)'", text)
        if m1:
            url = m1.group(1)

        m2 = re.search(r"defaultValue:\s*\n\s*'([^']+\.[^']+)'\s*,\s*\)\s*;", text)
        if m2:
            # This is a loose heuristic; if it fails, we just return empty.
            key = m2.group(1)

        # More direct: look for SUPABASE_ANON_KEY defaultValue block
        m3 = re.search(r"SUPABASE_ANON_KEY'[\s\S]*?defaultValue:\s*[\s\S]*?'([^']+)'", text)
        if m3:
            key = m3.group(1)

        if url and key:
            return url, key

    return "", ""


@dataclass(frozen=True)
class TableSpec:
    name: str
    columns: Set[str]


def _strip_sql_comments(sql: str) -> str:
    # Remove /* */ blocks
    sql = re.sub(r"/\*.*?\*/", "", sql, flags=re.S)
    # Remove -- to end of line
    sql = re.sub(r"--.*?$", "", sql, flags=re.M)
    return sql


def _parse_create_table_columns(sql_file: Path) -> Dict[str, Set[str]]:
    """Parse a subset of Postgres CREATE TABLE statements.

    This is intentionally simple; it aims to extract column names from schema files in this repo.
    """

    if not sql_file.exists():
        raise FileNotFoundError(f"Schema file not found: {sql_file}")

    sql = _strip_sql_comments(sql_file.read_text(encoding="utf-8"))

    # Matches: create table [if not exists] public.table_name (
    pattern = re.compile(
        r"create\s+table\s+(?:if\s+not\s+exists\s+)?(?:public\.)?([a-zA-Z_][a-zA-Z0-9_]*)\s*\((.*?)\)\s*;",
        flags=re.I | re.S,
    )

    tables: Dict[str, Set[str]] = {}

    for match in pattern.finditer(sql):
        table = match.group(1)
        body = match.group(2)

        cols: Set[str] = set()
        for raw_line in body.split("\n"):
            line = raw_line.strip().rstrip(",")
            if not line:
                continue

            # Skip constraints/keys/index-like lines
            lower = line.lower()
            if lower.startswith(
                (
                    "constraint ",
                    "primary key",
                    "foreign key",
                    "unique ",
                    "check ",
                    "exclude ",
                    "references ",
                )
            ):
                continue

            # Column line: <name> <type> ...
            first_token = re.split(r"\s+", line, maxsplit=1)[0]
            # Handle quoted identifiers
            if first_token.startswith('"') and first_token.endswith('"'):
                first_token = first_token[1:-1]

            if re.match(r"^[a-zA-Z_][a-zA-Z0-9_]*$", first_token):
                cols.add(first_token)

        if cols:
            tables[table] = cols

    return tables


def _expected_schema(which: str) -> Dict[str, TableSpec]:
    if which == "docx":
        tables = _parse_create_table_columns(DOCX_SQL)
        # calendar_events lives in its own SQL in this repo.
        if DOCX_CALENDAR_SQL.exists():
            cal = _parse_create_table_columns(DOCX_CALENDAR_SQL)
            if "calendar_events" in cal:
                tables["calendar_events"] = cal["calendar_events"]
    elif which == "legacy":
        tables = _parse_create_table_columns(LEGACY_SQL)
    else:
        raise ValueError("which must be 'docx' or 'legacy'")

    return {name: TableSpec(name=name, columns=cols) for name, cols in tables.items()}


def _print_header(title: str) -> None:
    print("\n" + title)
    print("=" * len(title))


def _diff_schema(
    expected: Dict[str, TableSpec],
    actual: Dict[str, Set[str]],
) -> int:
    missing_tables = sorted(set(expected.keys()) - set(actual.keys()))
    extra_tables = sorted(set(actual.keys()) - set(expected.keys()))

    col_missing: List[Tuple[str, List[str]]] = []
    col_extra: List[Tuple[str, List[str]]] = []

    for tname, spec in expected.items():
        if tname not in actual:
            continue
        missing_cols = sorted(spec.columns - actual[tname])
        extra_cols = sorted(actual[tname] - spec.columns)
        if missing_cols:
            col_missing.append((tname, missing_cols))
        if extra_cols:
            col_extra.append((tname, extra_cols))

    problems = 0

    _print_header("Tables")
    if not missing_tables and not extra_tables:
        print("OK: table set matches")
    else:
        problems += 1
        if missing_tables:
            print("Missing tables:")
            for t in missing_tables:
                print(f"  - {t}")
        if extra_tables:
            print("Extra tables:")
            for t in extra_tables:
                print(f"  - {t}")

    _print_header("Columns")
    if not col_missing and not col_extra:
        print("OK: column sets match for shared tables")
    else:
        problems += 1
        if col_missing:
            print("Missing columns:")
            for t, cols in col_missing:
                print(f"  - {t}: {', '.join(cols)}")
        if col_extra:
            print("Extra columns:")
            for t, cols in col_extra:
                print(f"  - {t}: {', '.join(cols)}")

    return problems


def _load_actual_schema_exact(database_url: str) -> Dict[str, Set[str]]:
    try:
        import psycopg
    except Exception as exc:  # pragma: no cover
        raise RuntimeError(
            "psycopg is required for --mode exact. Install it (pip install psycopg[binary])"
        ) from exc

    conn = psycopg.connect(database_url)
    try:
        cur = conn.cursor()
        cur.execute(
            """
            SELECT table_name, column_name
            FROM information_schema.columns
            WHERE table_schema = 'public'
            ORDER BY table_name, ordinal_position
            """
        )
        rows = cur.fetchall()
    finally:
        conn.close()

    actual: Dict[str, Set[str]] = {}
    for table_name, column_name in rows:
        actual.setdefault(table_name, set()).add(column_name)
    return actual


def _load_actual_schema_rest(
    supabase_url: str,
    supabase_key: str,
    expected: Dict[str, TableSpec],
    tables_to_probe: Set[str],
) -> Dict[str, Set[str]]:
    """Best-effort schema probe by probing columns via PostgREST.

    This is not a full introspection endpoint; we probe expected tables/columns and
    record what we can confirm.
    """

    try:
        from supabase import create_client
    except Exception as exc:  # pragma: no cover
        raise RuntimeError("supabase-py is required for --mode rest") from exc

    client = create_client(supabase_url, supabase_key)

    Status = Literal["present", "missing", "unknown"]

    # Build expected columns from local SQL for relevant tables.
    expected_all: Dict[str, Set[str]] = {}
    for name, spec in expected.items():
        if name in tables_to_probe:
            expected_all[name] = set(spec.columns)

    result: Dict[str, Dict[str, Status]] = {}

    for table, expected_cols in expected_all.items():
        table_map: Dict[str, Status] = {}

        # Establish whether table exists at all (vs. RLS/privileges).
        seed_col = next(iter(sorted(expected_cols)), "*")
        try:
            client.table(table).select(seed_col).limit(1).execute()
        except Exception as exc:
            msg = str(exc).lower()
            if "could not find the table" in msg or ("not found" in msg and "table" in msg):
                # Table missing: don't bother probing columns
                result[table] = {}
                continue
            if (
                "permission denied" in msg
                or "insufficient privilege" in msg
                or "unauthorized" in msg
                or "forbidden" in msg
                or "jwt" in msg
            ):
                # Table exists but we can't see anything.
                for c in expected_cols:
                    table_map[c] = "unknown"
                result[table] = table_map
                continue
            # Other errors: proceed to per-column probes; may still succeed.

        for col in sorted(expected_cols):
            try:
                client.table(table).select(col).limit(1).execute()
                table_map[col] = "present"
            except Exception as exc:
                msg = str(exc).lower()
                if "column" in msg and ("does not exist" in msg or "unknown" in msg):
                    table_map[col] = "missing"
                    continue
                if (
                    "permission denied" in msg
                    or "insufficient privilege" in msg
                    or "unauthorized" in msg
                    or "forbidden" in msg
                    or "jwt" in msg
                ):
                    table_map[col] = "unknown"
                    continue
                # Default: unknown
                table_map[col] = "unknown"

        result[table] = table_map

    # Convert to the old return type: confirmed-present columns only.
    confirmed: Dict[str, Set[str]] = {}
    for t, cmap in result.items():
        present = {c for c, st in cmap.items() if st == "present"}
        confirmed[t] = present

    # Attach full status map for the caller via an attribute.
    setattr(_load_actual_schema_rest, "_status_map", result)
    return confirmed


def main(argv: Optional[List[str]] = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--expected", choices=["docx", "legacy"], default="docx")
    parser.add_argument("--mode", choices=["exact", "rest"], default="rest")
    parser.add_argument("--database-url", default=os.environ.get("DATABASE_URL", ""))
    parser.add_argument("--supabase-url", default=os.environ.get("SUPABASE_URL", ""))
    parser.add_argument(
        "--supabase-key",
        default=os.environ.get("SUPABASE_KEY", os.environ.get("SUPABASE_ANON_KEY", "")),
    )

    args = parser.parse_args(argv)

    expected = _expected_schema(args.expected)

    if args.mode == "exact":
        if not args.database_url:
            print("Missing DATABASE_URL for --mode exact")
            return 2
        _print_header("Connection")
        print("Mode: exact (information_schema)")
        print("Expected:", args.expected)
        actual = _load_actual_schema_exact(args.database_url)
        return _diff_schema(expected, actual)

    if not args.supabase_url or not args.supabase_key:
        auto_url, auto_key = _auto_supabase_from_workspace()
        if not args.supabase_url:
            args.supabase_url = auto_url
        if not args.supabase_key:
            args.supabase_key = auto_key

    if not args.supabase_url or not args.supabase_key:
        print("Missing SUPABASE_URL / SUPABASE_KEY for --mode rest")
        return 2

    _print_header("Connection")
    print("Mode: rest (best-effort PostgREST probe)")
    print("Expected:", args.expected)
    print("Supabase URL:", args.supabase_url)
    key_kind = "service" if "service_role" in args.supabase_key else "anon/unknown"
    print("Key:", key_kind)

    if args.expected == "docx":
        tables_to_probe = {
            "care_space",
            "care_team_member",
            "user_profile",
            "medication",
            "medication_log",
            "symptom_log",
            "quick_notes",
            "moment",
            "calendar_events",
        }
    else:
        tables_to_probe = {
            "care_teams",
            "members",
            "medications",
            "dose_logs",
            "symptom_events",
            "observations",
            "moments",
            "calendar_events",
        }

    actual_probe = _load_actual_schema_rest(
        args.supabase_url,
        args.supabase_key,
        expected,
        tables_to_probe,
    )

    status_map = getattr(_load_actual_schema_rest, "_status_map", {})

    # REST probe is not full; build a partial 'actual' keyed by probed tables.
    actual: Dict[str, Set[str]] = actual_probe

    _print_header("Results")
    if not actual:
        print("No tables could be probed (likely permissions/RLS or wrong URL/key).")
        return 1

    missing_tables = []
    # status_map entries with empty dict are treated as missing tables
    for t, cmap in status_map.items():
        if cmap == {}:
            missing_tables.append(t)

    if missing_tables:
        print("Missing tables:")
        for t in sorted(missing_tables):
            print(f"  - {t}")

    print("Probed tables (column status counts):")
    had_missing_cols = False
    for t in sorted(status_map.keys()):
        cmap = status_map[t]
        if cmap == {}:
            continue
        present = sum(1 for v in cmap.values() if v == "present")
        missing = sum(1 for v in cmap.values() if v == "missing")
        unknown = sum(1 for v in cmap.values() if v == "unknown")
        print(f"  - {t}: present={present}, missing={missing}, unknown={unknown}")
        if missing > 0:
            had_missing_cols = True
            missing_cols = [c for c, st in cmap.items() if st == "missing"]
            print(f"    missing: {', '.join(sorted(missing_cols))}")

    if had_missing_cols or missing_tables:
        print("\nSchema mismatches detected (or table missing).")
        print("If many columns show unknown, re-run with a service role key or use --mode exact.")
        return 1

    print("\nOK: no missing tables/columns detected by REST probe.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
