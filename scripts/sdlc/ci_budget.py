"""Ratchet budgets for `flutter analyze` errors and `flutter test` failures.

CLI:
  python3 scripts/sdlc/ci_budget.py --analyze analyze.txt --budget 40
  python3 scripts/sdlc/ci_budget.py --tests test.txt --budget 38
Prints the count and exits 1 when over budget (or when the test summary cannot be parsed).
Budgets only ever ratchet down.
"""
import argparse
import re
import sys
from pathlib import Path
from typing import Optional

_ANALYZER_ERROR_RE = re.compile(r"^\s*error • ", re.MULTILINE)
# `flutter analyze` always ends with one of these; without it the run crashed or printed nothing.
_ANALYZER_SUMMARY_RE = re.compile(r"^\s*(?:No issues found!|\d+ issues? found\.)", re.MULTILINE)
# Progress lines look like `00:10 +1696 ~3 -38: Some tests failed.` / `00:10 +9: All tests passed!`
_TEST_PROGRESS_RE = re.compile(r"^\s*\d+:\d+\s+\+\d+(?:\s+~\d+)?(?:\s+-(\d+))?:", re.MULTILINE)


def count_analyzer_errors(text: str) -> Optional[int]:
    """Error count, or None when the analyzer summary line is missing (fail closed)."""
    if not _ANALYZER_SUMMARY_RE.search(text):
        return None
    return len(_ANALYZER_ERROR_RE.findall(text))


def count_test_failures(text: str) -> Optional[int]:
    """Failure count from the last progress line, or None when no summary was printed."""
    matches = _TEST_PROGRESS_RE.findall(text)
    if not matches:
        return None
    return int(matches[-1] or 0)


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--analyze", help="file holding `flutter analyze` output")
    group.add_argument("--tests", help="file holding `flutter test` output")
    parser.add_argument("--budget", type=int, required=True)
    args = parser.parse_args(argv)

    if args.analyze:
        label = "analyzer errors"
        count = count_analyzer_errors(Path(args.analyze).read_text(encoding="utf-8", errors="replace"))
        if count is None:
            print("Could not find a flutter analyze summary line; failing.")
            return 1
    else:
        label = "test failures"
        count = count_test_failures(Path(args.tests).read_text(encoding="utf-8", errors="replace"))
        if count is None:
            print("Could not find a flutter test summary line; failing.")
            return 1

    print(f"{label}: {count} (budget {args.budget})")
    return 0 if count <= args.budget else 1


if __name__ == "__main__":
    sys.exit(main())
