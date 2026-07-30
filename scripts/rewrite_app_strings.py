#!/usr/bin/env python3
"""Surgically rewrite lib/core/constants/app_strings.dart so every extracted
declaration calls getTranslatedString(key, fallback[, params]) instead of an
inline AppLocale.isBangla ternary or a plain English-only literal.

Only touches declarations that extract_translations.py successfully
classified (i.e. appear in its `entries` output with a non-null `key`).
Everything else -- unhandled edge cases, invariant bilingual lockups, and
consts absorbed into a dispatch/sibling entry -- is left byte-for-byte
untouched.

Re-derives byte offsets independently (not trusting cached positions from a
separate process), so this is safe to re-run against a freshly-edited file.

Usage:
    python3 scripts/rewrite_app_strings.py            # writes the file
    python3 scripts/rewrite_app_strings.py --dry-run   # prints a diff only
"""
import json
import re
import subprocess
import sys

sys.path.insert(0, "scripts")
from extract_translations import (  # noqa: E402
    DISPATCH_FUNCS,
    find_statement_end,
)

SRC = "lib/core/constants/app_strings.dart"


def dart_escape(s):
    return (
        s.replace("\\", "\\\\")
        .replace("'", "\\'")
        .replace("$", "\\$")
        .replace("\n", "\\n")
    )


def build_lookups(entries):
    simple = {}
    dispatch = {}
    for e in entries:
        if e.get("key") is None:
            continue
        if e.get("dispatch_code") is not None:
            dispatch[(e["class"], e["member"], e["dispatch_code"])] = e
        else:
            simple[(e["class"], e["member"])] = e
    return simple, dispatch


def make_simple_replacement(entry):
    key = entry["key"]
    fallback = dart_escape(entry["english"])
    if entry["kind"] == "param":
        params = list(dict.fromkeys(entry["params"]))  # de-dupe, preserve order
        param_sig = ", ".join(entry["dart_param_types"])
        params_map = ", ".join(f"'{p}': '${p}'" for p in params)
        return (
            f"static String {entry['member']}({param_sig}) => "
            f"getTranslatedString('{key}', '{fallback}', params: {{{params_map}}});"
        )
    return f"static String get {entry['member']} => getTranslatedString('{key}', '{fallback}');"


def main():
    dry_run = "--dry-run" in sys.argv

    raw = subprocess.run(
        [sys.executable, "scripts/extract_translations.py"],
        capture_output=True,
        text=True,
        check=True,
    )
    report = json.loads(raw.stdout)
    simple_lookup, dispatch_lookup = build_lookups(report["entries"])

    text = open(SRC, encoding="utf-8").read()
    class_re = re.compile(r"^abstract final class (\w+)", re.M)
    class_matches = list(class_re.finditer(text))

    edits = []  # (start, end, replacement_text)
    const_re = re.compile(r"static const String (\w+)\s*=")
    getter_re = re.compile(r"static String\??\s+get (\w+)\s*=>")
    func_re = re.compile(r"static String\??\s+(\w+)\(([^)]*)\)\s*(=>|\{)")
    case_re = re.compile(r"(case\s+'(?:[^'\\]|\\.)*'\s*:\s*)return\s+[^;]+;", re.S)

    for ci, cm in enumerate(class_matches):
        cls = cm.group(1)
        body_start = text.index("{", cm.end()) + 1
        body_end = class_matches[ci + 1].start() if ci + 1 < len(class_matches) else len(text)
        body_end = text.rindex("}", body_start, body_end)

        pos = body_start
        stmt_re = re.compile(r"static\s+(?:const\s+)?String\??\s*")
        while True:
            m = stmt_re.search(text, pos, body_end)
            if not m:
                break
            stmt_start = m.start()
            stmt_end = find_statement_end(text, stmt_start)
            raw_stmt = text[stmt_start:stmt_end]
            pos = stmt_end

            cm_const = const_re.match(raw_stmt)
            cm_getter = getter_re.match(raw_stmt)
            cm_func = func_re.match(raw_stmt)

            if cm_func and cm_func.group(1) in DISPATCH_FUNCS and cm_func.group(3) == "{":
                member = cm_func.group(1)
                for case_m in case_re.finditer(raw_stmt):
                    case_text = case_m.group(0)
                    code_m = re.match(r"case\s+'((?:[^'\\]|\\.)*)'", case_text)
                    code = code_m.group(1)
                    entry = dispatch_lookup.get((cls, member, code))
                    if entry is None:
                        continue
                    abs_start = stmt_start + case_m.start()
                    abs_end = stmt_start + case_m.end()
                    prefix = case_m.group(1)
                    replacement = prefix + f"return getTranslatedString('{entry['key']}', '{dart_escape(entry['english'])}');"
                    edits.append((abs_start, abs_end, replacement))
                continue

            member = None
            if cm_const:
                member = cm_const.group(1)
            elif cm_getter:
                member = cm_getter.group(1)
            elif cm_func and cm_func.group(3) == "=>":
                member = cm_func.group(1)

            if member is None:
                continue

            entry = simple_lookup.get((cls, member))
            if entry is None:
                continue

            if entry["kind"] == "param":
                entry = dict(entry)
                entry["dart_param_types"] = extract_param_decls(cm_func.group(2))

            replacement = make_simple_replacement(entry)
            edits.append((stmt_start, stmt_end, replacement))

    edits.sort(key=lambda e: e[0])
    for i in range(1, len(edits)):
        if edits[i][0] < edits[i - 1][1]:
            raise RuntimeError(f"overlapping edits at {edits[i]} vs {edits[i-1]}")

    out = []
    cursor = 0
    for start, end, replacement in edits:
        out.append(text[cursor:start])
        out.append(replacement)
        cursor = end
    out.append(text[cursor:])
    new_text = "".join(out)

    print(f"Applied {len(edits)} edits.", file=sys.stderr)

    if dry_run:
        sys.stdout.write(new_text)
    else:
        with open(SRC, "w", encoding="utf-8") as f:
            f.write(new_text)
        print(f"✓ Wrote {SRC}", file=sys.stderr)


def extract_param_decls(sig):
    """Return each parameter's full declaration text (type + name), e.g.
    ['int n', 'String? type'], preserving original types exactly."""
    parts = [p.strip() for p in sig.split(",") if p.strip()]
    return parts


if __name__ == "__main__":
    main()
