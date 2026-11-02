#!/usr/bin/env python3
"""Generate lib/l10n/catalogs.g.dart from strings_*.json files.

Usage:
    python3 tool/generate_catalogs.py            # generate + report
    python3 tool/generate_catalogs.py --check    # report only, no write

Run this after adding/editing any strings_*.json file.

FIXES in this version:
  1. Plain string keys ('continueBtn') — matches your CURRENT
     catalogs.g.dart exactly, and no Dart import needed. The
     old script wrote AppStrings.ok keys, which silently changed
     the file's shape on every regeneration.
  2. Correct Dart string escaping, in the right order:
     backslash first, then single quote, newline, dollar.
  3. Built-in translation report: flags languages that are
     still English placeholders so you know which ones to hide
     from the picker or send for translation.
"""

import json
import sys
from pathlib import Path

L10N_DIR = Path(__file__).resolve().parent.parent / "lib" / "l10n"
OUT_FILE = L10N_DIR / "catalogs.g.dart"

REQUIRED = {"en"}


def dart_string(value: str) -> str:
    """Escape a value for a Dart single-quoted string literal.

    ORDER MATTERS: backslash must be escaped first, otherwise
    the escapes added later get double-escaped.
    """
    return (
        value.replace("\\", "\\\\")
        .replace("'", "\\'")
        .replace("\n", "\\n")
        .replace("\r", "\\r")
        .replace("$", "\\$")
    )


def main() -> None:
    check_only = "--check" in sys.argv

    files = sorted(L10N_DIR.glob("strings_*.json"))
    if not files:
        raise SystemExit(f"No strings_*.json found in {L10N_DIR}")

    codes = []
    catalogs = {}
    for f in files:
        code = f.stem.replace("strings_", "")
        if not code:
            continue
        with f.open(encoding="utf-8") as fh:
            catalogs[code] = json.load(fh)
        codes.append(code)

    missing = REQUIRED - set(codes)
    if missing:
        raise SystemExit(f"Missing required files: {missing}")

    en = catalogs["en"]

    # ---- lines of the generated Dart file ----
    lines = [
        "// GENERATED FILE. Source: lib/l10n/strings_<code>.json.",
        "// Regenerate from the JSON catalogs; do not edit manually.",
        "",
    ]

    var_names = {}
    for code in codes:
        # Dart identifiers: avoid reserved words like `in`.
        var = f"_{code}" if code.isidentifier() and code not in {
            "in", "is", "as", "do", "if", "for",
        } else f"_{code}_x"
        var_names[code] = var

        lines.append(f"/// Generated from lib/l10n/strings_{code}.json")
        lines.append(f"const Map<String, String> {var} = {{")
        for key in en.keys():  # stable English order
            value = catalogs[code].get(key)
            if value is None:
                continue  # absent -> English fallback at runtime
            lines.append(f"  '{dart_string(key)}': \"{dart_string(value)}\",")
        lines.append("};")
        lines.append("")

    lines.append("/// code -> catalog. Generated from lib/l10n/strings_*.json")
    lines.append("const Map<String, Map<String, String>> catalogs = {")
    for code in codes:
        lines.append(f"  '{code}': {var_names[code]},")
    lines.append("};")
    lines.append("")

    if not check_only:
        OUT_FILE.write_text("\n".join(lines), encoding="utf-8")
        print(f"Generated {OUT_FILE} with {len(codes)} languages.")

    # ---- translation report (issue 2) ----
    print("\n=== TRANSLATION STATUS ===")
    ready, placeholder = [], []
    for code in codes:
        if code == "en":
            continue
        cat = catalogs[code]
        translated = sum(
            1 for k, v in en.items()
            if k in cat and cat[k] != en[k]
        )
        pct = 100 * translated // len(en)
        # A language is "real" if at least half differs from English.
        (ready if pct >= 50 else placeholder).append((code, pct))

    print(f"\nTranslated (>=50% differs from English) — {len(ready)}:")
    for code, pct in sorted(ready, key=lambda x: -x[1]):
        print(f"  {code}: {pct}%")

    print(f"\nStill English placeholders (<50%) — {len(placeholder)}:")
    for code, pct in sorted(placeholder):
        print(f"  {code}: {pct}%")

    print(
        "\nTIP: until a placeholder language is translated, either "
        "remove it from AppLanguages.all (picker) or accept that it "
        "shows English via the fallback."
    )


if __name__ == "__main__":
    main()