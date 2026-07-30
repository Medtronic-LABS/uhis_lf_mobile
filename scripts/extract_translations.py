#!/usr/bin/env python3
"""Extract translatable strings from lib/core/constants/app_strings.dart.

Parses the Dart source with a small brace/quote-aware scanner (not line
regexes, since ternaries and dispatch functions span multiple lines in
inconsistent ways) and produces a master table of
    (key, class, member, kind, english, bangla_or_None, params)
entries, plus a report of anything it couldn't confidently classify (left
untouched in the source rather than risking a wrong rewrite).

Usage:
    python3 scripts/extract_translations.py > /tmp/translations_report.json
"""
import json
import re
import sys

SRC = "lib/core/constants/app_strings.dart"

# (class, member) pairs of plain consts that are only ever referenced as the
# RHS of a dispatch switch case (e.g. `symptomConvulsions`, referenced from
# `symptomLabel`'s switch). Populated during dispatch-case resolution, then
# used to drop these from the top-level entry list in main() -- the dispatch
# entry (keyed e.g. `Triage.symptom.convulsions`) already covers the same
# string, so keeping both would just duplicate every dispatch-backed string.
DISPATCH_REFERENCED = set()

# Dispatch (switch-on-string-code) functions we know how to safely convert.
# Each maps to a stable key prefix used for its case entries.
# NOTE: symptomBangla is deliberately excluded -- it's dead code (zero call
# sites), shares its case-set with symptomLabel, and its cases resolve to the
# *Bn sibling consts directly. Including it would emit a second, colliding
# entry per symptom code with the Bangla text mislabeled as "english".
DISPATCH_FUNCS = {
    "symptomLabel": "symptom",
    "fieldLabel": "field",
    "sectionTitle": "section",
    "message": "message",
    "rationale": "rationale",
}

# Exact (class, member) pairs to leave completely untouched:
#  - bilingual lockups always shown together (not locale alternates)
#  - consts only reachable through symptomBangla, which is dead code (zero
#    call sites) that we deliberately don't parse (see DISPATCH_FUNCS) --
#    these two symptom codes have no case in the live symptomLabel switch at
#    all, so there's no English string to pair them with.
INVARIANT = {
    ("LockStrings", "leapwell"),
    ("LockStrings", "aponSushashthya"),
    ("LockStrings", "aponSushashthyaBn"),
    ("PatientContextStrings", "greetingBangla"),
    ("PatientContextStrings", "greetingEnglish"),
    ("VisitTriageStrings", "skAsksBangla"),
    ("VisitTriageStrings", "skAsksEnglish"),
    ("TriageStrings", "symptomEyePainBn"),
    ("TriageStrings", "symptomGradualVisionLossBn"),
    ("TriageStrings", "symptomReducedVisionBn"),
    ("TriageStrings", "symptomNoFamilyPlanningBn"),
    ("TriageStrings", "symptomWantsContraceptionBn"),
}

# Some consts carry a hand-written Bangla translation as a sibling const
# whose name isn't a simple <name>Bn suffix (it replaces a "Title" infix
# instead), e.g. strokeSignTitle / strokeSignBn. Mapped explicitly here;
# the simple <name>Bn convention (the vast majority, e.g. symptomConvulsions
# / symptomConvulsionsBn) is handled generically in merge_bn_siblings().
BN_SIBLING_OVERRIDES = {
    "strokeSignBn": "strokeSignTitle",
    "morningHeadachesBn": "morningHeadachesTitle",
    "chestTightnessBn": "chestTightnessTitle",
    "highSaltBn": "highSaltTitle",
    "familyHistoryBn": "familyHistoryTitle",
}


def unescape_dart(s):
    return (
        s.replace("\\'", "'")
        .replace('\\"', '"')
        .replace("\\n", "\n")
        .replace("\\\\", "\\")
    )


def find_statement_end(text, start):
    """From `start` (at 'static'), find the index just after the statement's
    terminating ';' (arrow body) or matching '}' (block body), respecting
    nested braces/parens/brackets and single/double-quoted strings."""
    i = start
    n = len(text)
    depth_brace = depth_paren = 0
    in_string = None
    is_block = None
    while i < n:
        c = text[i]
        if in_string:
            if c == "\\":
                i += 2
                continue
            if c == in_string:
                in_string = None
            i += 1
            continue
        if c in ("'", '"'):
            in_string = c
            i += 1
            continue
        if c == "(":
            depth_paren += 1
        elif c == ")":
            depth_paren -= 1
        elif c == "{":
            depth_brace += 1
            if is_block is None and depth_paren == 0:
                is_block = True
        elif c == "}":
            depth_brace -= 1
            if is_block and depth_brace == 0:
                return i + 1
        elif c == ";" and depth_paren == 0 and depth_brace == 0:
            if is_block is None:
                is_block = False
            if not is_block:
                return i + 1
        i += 1
    raise ValueError(f"unterminated statement starting at {start}")


def split_top_level_ternary(expr):
    """If expr is exactly `COND ? A : B` at the top level (not nested inside
    another ?: or inside parens/strings), return (cond, a, b). Else None."""
    depth = 0
    in_string = None
    q_idx = None
    i = 0
    n = len(expr)
    while i < n:
        c = expr[i]
        if in_string:
            if c == "\\":
                i += 2
                continue
            if c == in_string:
                in_string = None
            i += 1
            continue
        if c in ("'", '"'):
            in_string = c
        elif c in "([{":
            depth += 1
        elif c in ")]}":
            depth -= 1
        elif c == "?" and depth == 0 and expr[i : i + 2] != "?.":
            if q_idx is not None:
                return None  # more than one top-level '?' -> nested, bail
            q_idx = i
        elif c == ":" and depth == 0 and q_idx is not None:
            cond = expr[:q_idx].strip()
            a = expr[q_idx + 1 : i].strip()
            b = expr[i + 1 :].strip()
            # Reject if either branch itself still has a top-level ternary/paren-wrapped ternary
            if split_top_level_ternary(a) or split_top_level_ternary(b):
                return None
            return cond, a, b
        i += 1
    return None


def _find_matching_brace(s, open_idx):
    """s[open_idx] == '{'. Return the index of its matching '}', skipping
    over any nested quoted strings (which may contain their own braces/quotes
    that must not confuse the depth count) and nested braces. Returns -1 if
    unterminated."""
    depth = 1
    i = open_idx + 1
    n = len(s)
    while i < n:
        c = s[i]
        if c == "\\":
            i += 2
            continue
        if c in ("'", '"'):
            quote = c
            i += 1
            while i < n:
                if s[i] == "\\":
                    i += 2
                    continue
                if s[i] == quote:
                    i += 1
                    break
                i += 1
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1


def _consume_body(body, out, params):
    """Append body's chars to `out`, converting $ident / ${expr} into
    {pN} placeholder tokens and recording each raw Dart expression into
    `params` (shared, running list, so multi-segment concatenation keeps
    consistent numbering). Returns False (caller should bail -> unhandled)
    if an interpolation block is malformed/unterminated."""
    i = 0
    while i < len(body):
        c = body[i]
        if c == "$" and i + 1 < len(body):
            if body[i + 1] == "{":
                j = _find_matching_brace(body, i + 1)
                if j == -1:
                    return False
                inner = body[i + 2 : j]
                out.append("{" + f"p{len(params)}" + "}")
                params.append(inner)
                i = j + 1
                continue
            else:
                m = re.match(r"[A-Za-z_]\w*", body[i + 1 :])
                if m:
                    inner = m.group(0)
                    out.append("{" + f"p{len(params)}" + "}")
                    params.append(inner)
                    i += 1 + len(inner)
                    continue
        out.append(c)
        i += 1
    return True


def _find_literal_end(s, pos):
    """s[pos] is an opening quote. Return the index of the matching closing
    quote, skipping over ${...} interpolation blocks (which may themselves
    contain nested quoted strings, e.g. `${n == 1 ? '' : 's'}`)."""
    quote = s[pos]
    i = pos + 1
    n = len(s)
    while i < n:
        c = s[i]
        if c == "\\":
            i += 2
            continue
        if c == quote:
            return i
        if c == "$" and i + 1 < n and s[i + 1] == "{":
            j = _find_matching_brace(s, i + 1)
            if j == -1:
                return -1
            i = j + 1
            continue
        i += 1
    return -1


def parse_string_literal(s):
    """s must be one or more adjacent string literals (Dart's implicit
    string-literal concatenation, e.g. 'part1 ' 'part2 ';), possibly with
    $var / ${expr} interpolation. Returns (text_with_tokens, param_refs)
    or None if not a bare literal/concatenation (e.g. a `+` operator, a
    trailing method call, or an interpolation too complex to safely
    templatize, like an inline ternary for pluralization)."""
    s = s.strip()
    n = len(s)
    pos = 0
    out = []
    params = []
    found_any = False
    while pos < n:
        if s[pos] not in ("'", '"'):
            return None
        j = _find_literal_end(s, pos)
        if j == -1:
            return None  # unterminated literal
        if not _consume_body(s[pos + 1 : j], out, params):
            return None
        found_any = True
        pos = j + 1
        while pos < n and s[pos] in " \t\n":
            pos += 1
        if pos >= n:
            break
        if s[pos] not in ("'", '"'):
            return None  # trailing junk after the literal(s) -- e.g. `+ x`
    if not found_any:
        return None
    return unescape_dart("".join(out)), params


BN_SUFFIXES = ("Bn", "Bengali")


def _candidate_base_names(member, suffix):
    stem = member[: -len(suffix)]
    yield stem  # symptomConvulsions + Bn
    yield stem + "Label"  # pregnantWoman + Label / Bengali
    yield stem + "English"  # greeting + English / Bangla (invariant pairs
    # are filtered separately, but harmless to also try here)


def merge_bn_siblings(entries):
    """Some plain consts carry a hand-written Bangla translation as a sibling
    const rather than an inline ternary, under one of a few naming
    conventions seen in this file: skOpenerPhrase/skOpenerPhraseBn,
    strokeSignTitle/strokeSignBn (BN_SIBLING_OVERRIDES), and
    pregnantWomanLabel/pregnantWomanBengali. Fold each sibling's value into
    its pair's `bangla` field in place, then drop the standalone entry so it
    doesn't show up as its own (mislabeled) row."""
    by_class_member = {(e["class"], e["member"]): e for e in entries}
    drop = []
    for e in entries:
        member = e["member"]
        if e["kind"] != "const":
            continue
        suffix = next((s for s in BN_SUFFIXES if member.endswith(s)), None)
        if suffix is None:
            continue
        if member in BN_SIBLING_OVERRIDES:
            candidates = [BN_SIBLING_OVERRIDES[member]]
        else:
            candidates = list(_candidate_base_names(member, suffix))
        base = next(
            (by_class_member.get((e["class"], c)) for c in candidates if by_class_member.get((e["class"], c))),
            None,
        )
        if base is not None:
            base["bangla"] = e["english"]
            drop.append(e)
    for e in drop:
        entries.remove(e)


def main():
    text = open(SRC, encoding="utf-8").read()

    class_re = re.compile(r"^abstract final class (\w+)", re.M)
    class_matches = list(class_re.finditer(text))

    entries = []
    unhandled = []
    consts_by_class = {}  # (class, member) -> literal value, for dispatch resolution

    for ci, cm in enumerate(class_matches):
        cls = cm.group(1)
        body_start = text.index("{", cm.end()) + 1
        body_end = class_matches[ci + 1].start() if ci + 1 < len(class_matches) else len(text)
        # Trim body_end back to this class's own closing brace (last '}' before next class)
        body_end = text.rindex("}", body_start, body_end)
        body = text[body_start:body_end]

        pos = 0
        stmt_re = re.compile(r"static\s+(?:const\s+)?String\??\s*")
        while True:
            m = stmt_re.search(body, pos)
            if not m:
                break
            stmt_start = m.start()
            try:
                stmt_end = find_statement_end(body, stmt_start)
            except ValueError as e:
                unhandled.append({"class": cls, "error": str(e)})
                break
            raw = body[stmt_start:stmt_end]
            pos = stmt_end
            result = classify_statement(cls, raw, consts_by_class)
            if result is None:
                unhandled.append({"class": cls, "raw": raw.strip()[:120]})
            elif isinstance(result, list):
                entries.extend(result)
            else:
                entries.append(result)

    merge_bn_siblings(entries)
    entries[:] = [
        e for e in entries if (e["class"], e["member"]) not in DISPATCH_REFERENCED
    ]

    # Assign unique keys: bare member name, unless it collides with another
    # class's member of the same name -> prefix with class name (Strings suffix
    # stripped).
    name_counts = {}
    for e in entries:
        name_counts[e["member"]] = name_counts.get(e["member"], 0) + 1

    for e in entries:
        if (e["class"], e["member"]) in INVARIANT:
            e["key"] = None  # signal: leave untouched, don't emit
            continue
        if e.get("dispatch_code") is not None:
            page = e["class"][:-7] if e["class"].endswith("Strings") else e["class"]
            e["key"] = f"{page}.{e['dispatch_group']}.{e['dispatch_code']}"
        elif name_counts[e["member"]] > 1:
            page = e["class"][:-7] if e["class"].endswith("Strings") else e["class"]
            e["key"] = f"{page}.{e['member']}"
        else:
            e["key"] = e["member"]

    out = {
        "entries": [e for e in entries if e.get("key") is not None],
        "skipped_invariant": [e for e in entries if e.get("key") is None],
        "unhandled": unhandled,
        "counts": {
            "total_entries": len([e for e in entries if e.get("key") is not None]),
            "unhandled": len(unhandled),
            "missing_bangla": len(
                [e for e in entries if e.get("key") is not None and not e.get("bangla")]
            ),
        },
    }
    json.dump(out, sys.stdout, ensure_ascii=False, indent=1)


def classify_statement(cls, raw, consts_by_class):
    raw = raw.strip()
    # --- const NAME = 'literal'; ---
    m = re.match(r"static const String (\w+)\s*=\s*(.+);\s*$", raw, re.S)
    if m:
        member, rhs = m.group(1), m.group(2)
        lit = parse_string_literal(rhs)
        if lit is None:
            return None
        english, params = lit
        if params:
            return None  # const can't interpolate; shouldn't happen
        consts_by_class[(cls, member)] = english
        return {
            "class": cls,
            "member": member,
            "kind": "const",
            "english": english,
            "bangla": None,
            "params": [],
            "dispatch_code": None,
        }

    # --- getter: static String get NAME => EXPR; ---
    m = re.match(r"static String\??\s+get (\w+)\s*=>\s*(.+);\s*$", raw, re.S)
    if m:
        member, expr = m.group(1), m.group(2).strip()
        return classify_expr(cls, member, expr, [], consts_by_class)

    # --- function: static String NAME(params) => EXPR; ---
    m = re.match(r"static String\??\s+(\w+)\(([^)]*)\)\s*=>\s*(.+);\s*$", raw, re.S)
    if m:
        member, paramsig, expr = m.group(1), m.group(2), m.group(3).strip()
        param_names = extract_param_names(paramsig)
        return classify_expr(cls, member, expr, param_names, consts_by_class)

    # --- dispatch: static String NAME(params) { switch (x) { case 'a': return EXPR; ... } } ---
    m = re.match(r"static String\??\s+(\w+)\(([^)]*)\)\s*\{(.+)\}\s*$", raw, re.S)
    if m and m.group(1) in DISPATCH_FUNCS:
        member, _paramsig, block = m.group(1), m.group(2), m.group(3)
        group = DISPATCH_FUNCS[member]
        case_re = re.compile(r"case\s+'((?:[^'\\]|\\.)*)'\s*:\s*return\s+([^;]+);", re.S)
        results = []
        for cm in case_re.finditer(block):
            code, ret_expr = cm.group(1), cm.group(2).strip()
            lit = parse_string_literal(ret_expr)
            bangla = None
            if lit is not None:
                english, params = lit
                if params:
                    continue  # skip parametrized dispatch cases (rare/none expected)
            else:
                # bare identifier referencing a const in the same class
                ident = ret_expr.strip()
                if not re.match(r"^\w+$", ident):
                    continue
                english = consts_by_class.get((cls, ident))
                if english is None:
                    continue
                bangla = consts_by_class.get((cls, ident + "Bn"))
                DISPATCH_REFERENCED.add((cls, ident))
                if bangla is not None:
                    DISPATCH_REFERENCED.add((cls, ident + "Bn"))
            results.append(
                {
                    "class": cls,
                    "member": member,
                    "kind": "dispatch",
                    "english": english,
                    "bangla": bangla,
                    "params": [],
                    "dispatch_code": code,
                    "dispatch_group": group,
                }
            )
        return results if results else None

    return None


def extract_param_names(sig):
    names = []
    for part in sig.split(","):
        part = part.strip()
        if not part:
            continue
        m = re.search(r"(\w+)\s*$", part)
        if m:
            names.append(m.group(1))
    return names


def classify_expr(cls, member, expr, param_names, consts_by_class):
    tern = split_top_level_ternary(expr)
    if tern is None:
        # not a ternary -> maybe a bare literal (English-only, no Bangla yet)
        lit = parse_string_literal(expr)
        if lit is None:
            return None
        english, interp = lit
        params = resolve_params(interp, param_names)
        if params is None:
            return None
        english = rekey_tokens(english, params, params)
        consts_by_class[(cls, member)] = english
        return {
            "class": cls,
            "member": member,
            "kind": "param" if param_names else "simple",
            "english": english,
            "bangla": None,
            "params": [p["name"] for p in params],
            "dispatch_code": None,
        }

    cond, a, b = tern
    if cond != "AppLocale.isBangla":
        return None
    bn_lit = parse_string_literal(a)
    en_lit = parse_string_literal(b)
    if bn_lit is None or en_lit is None:
        return None
    bangla, bn_interp = bn_lit
    english, en_interp = en_lit
    params_en = resolve_params(en_interp, param_names)
    params_bn = resolve_params(bn_interp, param_names)
    if params_en is None or params_bn is None:
        return None
    # Re-key both branches' {pN} tokens to the real (English-side) param names,
    # so callers can substitute {realName} consistently in either language.
    bangla = rekey_tokens(bangla, params_bn, params_en)
    english = rekey_tokens(english, params_en, params_en)
    consts_by_class[(cls, member)] = english
    return {
        "class": cls,
        "member": member,
        "kind": "param" if param_names else "simple",
        "english": english,
        "bangla": bangla,
        "params": [p["name"] for p in params_en],
        "dispatch_code": None,
    }


def resolve_params(interp_exprs, param_names):
    """Map each raw interpolated Dart expression (e.g. 'n', 'm') to a
    param name. Only accept bare identifiers that are actually one of this
    declaration's own parameters -- anything else (a nested ternary, a
    method call, or a reference to some other static member) means we bail
    and leave the whole declaration unhandled rather than guess."""
    out = []
    for e in interp_exprs:
        e = e.strip()
        if e not in param_names:
            return None
        out.append({"name": e})
    return out


def rekey_tokens(text, from_params, to_params):
    """text has {p0}, {p1}, ... referring to from_params[i]['name']; rewrite
    to the SAME semantic param name (from to_params) by position-matched name,
    falling back to positional if names differ 1:1 in same order."""
    if len(from_params) != len(to_params):
        return text
    for i, (fp, tp) in enumerate(zip(from_params, to_params)):
        text = text.replace("{p" + str(i) + "}", "{" + tp["name"] + "}")
    return text


if __name__ == "__main__":
    main()
