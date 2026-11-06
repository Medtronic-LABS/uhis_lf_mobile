"""commit-msg check: subject must reference an issue or follow Conventional Commits.

CLI: python3 scripts/sdlc/commit_msg.py <message-file>   (exits 1 with the error)
"""
import re
import sys
from pathlib import Path
from typing import Optional

_ISSUE_RE = re.compile(r"#\d+")
_CONVENTIONAL_RE = re.compile(
    r"^(feat|fix|chore|docs|refactor|test|perf|build|ci|style|revert)(\(.+\))?!?: "
)
_AUTO_PREFIXES = ("Merge ", "Revert ", "fixup! ", "squash! ", "amend! ")

ERROR = (
    "Commit subject must reference an issue (#123) or start with a Conventional Commit "
    "type, e.g. 'feat(scope): summary'."
)


def check(message: str) -> Optional[str]:
    """Return an error string, or None when the message is acceptable."""
    lines = message.strip().splitlines()
    subject = lines[0].strip() if lines else ""
    if subject.startswith(_AUTO_PREFIXES):
        return None
    if _ISSUE_RE.search(subject) or _CONVENTIONAL_RE.match(subject):
        return None
    return ERROR


def main(argv: Optional[list[str]] = None) -> int:
    args = sys.argv[1:] if argv is None else argv
    if len(args) != 1:
        print("usage: commit_msg.py <message-file>", file=sys.stderr)
        return 2
    error = check(Path(args[0]).read_text(encoding="utf-8"))
    if error:
        print(error, file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
