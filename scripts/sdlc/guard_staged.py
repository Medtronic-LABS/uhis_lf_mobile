"""pre-commit check: block protected files and sensitive content in staged files.

CLI: python3 scripts/sdlc/guard_staged.py   (exits 1 listing `path: category`)
"""
import subprocess
import sys
from pathlib import Path
from typing import Callable, Optional

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from scripts.sdlc.patterns import find_sensitive, is_protected_path  # noqa: E402

MAX_BYTES = 1_000_000
FIXTURE_PREFIX = "scripts/sdlc/tests/"
PROTECTED_CATEGORY = "protected_path"


def check(paths: list[str], read: Callable[[str], str]) -> list[str]:
    """Return `path: category` problems for the staged paths."""
    problems: list[str] = []
    for path in paths:
        if is_protected_path(path):
            problems.append(f"{path}: {PROTECTED_CATEGORY}")
            continue
        if path.startswith(FIXTURE_PREFIX):
            continue
        try:
            content = read(path)
        except (UnicodeDecodeError, OSError):
            continue
        if len(content) > MAX_BYTES:
            continue
        problems.extend(f"{path}: {category}" for category in find_sensitive(content))
    return problems


def read_text_file(path: str) -> str:
    """Read a text file; binary or oversized files read as empty (not scanned)."""
    with open(path, "rb") as handle:
        data = handle.read(MAX_BYTES + 1)
    if len(data) > MAX_BYTES or b"\x00" in data:
        return ""
    return data.decode("utf-8", errors="replace")


def staged_paths() -> list[str]:
    done = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACM"],
        capture_output=True, text=True, check=True,
    )
    return [line for line in done.stdout.splitlines() if line]


def main(argv: Optional[list[str]] = None) -> int:
    problems = check(staged_paths(), read_text_file)
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
