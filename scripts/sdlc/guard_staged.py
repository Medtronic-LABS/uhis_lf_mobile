"""pre-commit check: block protected files and credentials in staged blobs.

Only credential categories are scanned in source (PHI categories apply to
issue/PR text, where source-style examples are not expected).

CLI: python3 scripts/sdlc/guard_staged.py   (exits 1 listing `path: category`)
"""
import subprocess
import sys
from pathlib import Path
from typing import Callable, Optional

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from scripts.sdlc.patterns import CREDENTIAL_CATEGORIES, find_sensitive, is_protected_path  # noqa: E402

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
            print(f"lw-guard: could not read staged {path}; skipped", file=sys.stderr)
            continue
        if len(content) > MAX_BYTES:
            continue
        categories = find_sensitive(content, CREDENTIAL_CATEGORIES)
        problems.extend(f"{path}: {category}" for category in categories)
    return problems


def decode_blob(data: bytes) -> str:
    """Decode text bytes; binary or oversized content reads as empty (not scanned)."""
    if len(data) > MAX_BYTES or b"\x00" in data:
        return ""
    return data.decode("utf-8", errors="replace")


def read_staged_blob(path: str, repo: Optional[str] = None) -> str:
    """Read the staged (index) version of a file, not the working tree."""
    command = ["git"] + (["-C", repo] if repo else []) + ["show", f":{path}"]
    try:
        done = subprocess.run(command, capture_output=True, check=True)
    except subprocess.CalledProcessError as error:
        raise OSError(f"cannot read staged blob for {path}") from error
    return decode_blob(done.stdout)


def staged_paths() -> list[str]:
    done = subprocess.run(
        ["git", "diff", "--cached", "--name-only", "--diff-filter=ACM"],
        capture_output=True, text=True, check=True,
    )
    return [line for line in done.stdout.splitlines() if line]


def main(argv: Optional[list[str]] = None) -> int:
    problems = check(staged_paths(), read_staged_blob)
    for problem in problems:
        print(problem, file=sys.stderr)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
