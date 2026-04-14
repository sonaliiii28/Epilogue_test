"""Extract tables (and some text) from a .docx file.

This repo's schema-of-truth is sometimes maintained in a Word document.
GitHub Copilot Chat attachments are not directly readable as workspace files,
so we keep a small helper that can parse a real .docx checked into the repo.

The script outputs:
  - A JSON payload with all extracted tables (rows/cells as plain text)
  - A best-effort Markdown preview to help humans verify parsing

Usage:
  python backend/extract_docx_tables.py path/to/schema.docx --out schema_tables.json
"""

from __future__ import annotations

import argparse
import json
import re
import zipfile
from pathlib import Path
from xml.etree import ElementTree as ET


_NS = {
    "w": "http://schemas.openxmlformats.org/wordprocessingml/2006/main",
}


def _cell_text(cell_el: ET.Element) -> str:
    # Word stores text in runs: w:t under w:r under w:p
    texts: list[str] = []
    for t in cell_el.findall(".//w:t", _NS):
        if t.text:
            texts.append(t.text)
    value = "".join(texts)
    # normalize whitespace a bit
    value = re.sub(r"\s+", " ", value).strip()
    return value


def _extract_tables(doc_xml: str) -> list[list[list[str]]]:
    root = ET.fromstring(doc_xml)
    tables: list[list[list[str]]] = []
    for tbl in root.findall(".//w:tbl", _NS):
        rows: list[list[str]] = []
        for tr in tbl.findall("./w:tr", _NS):
            row: list[str] = []
            for tc in tr.findall("./w:tc", _NS):
                row.append(_cell_text(tc))
            # skip entirely empty rows
            if any(c for c in row):
                rows.append(row)
        if rows:
            tables.append(rows)
    return tables


def _extract_paragraphs(doc_xml: str, limit: int = 2000) -> list[str]:
    root = ET.fromstring(doc_xml)
    paras: list[str] = []
    for p in root.findall(".//w:p", _NS):
        texts: list[str] = []
        for t in p.findall(".//w:t", _NS):
            if t.text:
                texts.append(t.text)
        value = re.sub(r"\s+", " ", "".join(texts)).strip()
        if value:
            paras.append(value)
        if len(paras) >= limit:
            break
    return paras


def docx_to_tables(path: Path, *, paragraph_limit: int = 2000) -> dict:
    if not path.exists() or path.suffix.lower() != ".docx":
        raise SystemExit(f"Not a .docx file: {path}")

    with zipfile.ZipFile(path) as z:
        try:
            doc_xml = z.read("word/document.xml").decode("utf-8")
        except KeyError as e:
            raise SystemExit("Invalid docx: missing word/document.xml") from e

    tables = _extract_tables(doc_xml)
    paragraphs = _extract_paragraphs(doc_xml, limit=paragraph_limit)
    return {
        "source": str(path),
        "tables": tables,
        "paragraphs_preview": paragraphs,
    }


def _tables_to_markdown(tables: list[list[list[str]]], max_tables: int = 25) -> str:
    lines: list[str] = []
    for i, table in enumerate(tables[:max_tables], start=1):
        lines.append(f"\n## Table {i}\n")
        if not table:
            continue
        # Render as a GitHub-flavored markdown table when possible.
        header = table[0]
        col_count = max(1, len(header))

        def norm_row(r: list[str]) -> list[str]:
            r2 = list(r) + [""] * (col_count - len(r))
            return r2[:col_count]

        header = norm_row(header)
        lines.append("| " + " | ".join(header) + " |")
        lines.append("| " + " | ".join(["---"] * col_count) + " |")
        for row in table[1:]:
            lines.append("| " + " | ".join(norm_row(row)) + " |")
    return "\n".join(lines).strip() + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(description="Extract tables from a .docx")
    parser.add_argument("docx", type=Path, help="Path to .docx")
    parser.add_argument(
        "--out",
        type=Path,
        default=None,
        help="Optional JSON output path (defaults to stdout)",
    )
    parser.add_argument(
        "--md",
        type=Path,
        default=None,
        help="Optional Markdown preview output path",
    )
    parser.add_argument(
        "--para-limit",
        type=int,
        default=2000,
        help="Max paragraphs to include in paragraphs_preview",
    )
    args = parser.parse_args()

    payload = docx_to_tables(args.docx, paragraph_limit=args.para_limit)
    tables = payload.get("tables", [])

    if args.md is not None:
        args.md.write_text(_tables_to_markdown(tables), encoding="utf-8")

    json_text = json.dumps(payload, indent=2, ensure_ascii=False)
    if args.out is not None:
        args.out.write_text(json_text, encoding="utf-8")
    else:
        print(json_text)


if __name__ == "__main__":
    main()
