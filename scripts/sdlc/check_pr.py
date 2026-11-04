"""Validate a pull request description and branch name.

CLI: python3 scripts/sdlc/check_pr.py --event "$GITHUB_EVENT_PATH"
Exits 1 (printing reasons, never matched values) when the PR is not ok.
"""
import argparse
import json
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from scripts.sdlc.patterns import BRANCH_RE, ISSUE_REF_RE, find_sensitive  # noqa: E402


@dataclass
class PrResult:
    has_issue_ref: bool
    branch_ok: bool
    sensitive: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return self.has_issue_ref and not self.sensitive


def evaluate(body: str, head_ref: str) -> PrResult:
    return PrResult(
        has_issue_ref=ISSUE_REF_RE.search(body) is not None,
        branch_ok=BRANCH_RE.match(head_ref) is not None,
        sensitive=find_sensitive(body),
    )


def describe(result: PrResult) -> list[str]:
    lines = []
    if not result.has_issue_ref:
        lines.append("PR body must link an issue, e.g. 'Closes #12' or 'Refs #12'.")
    if result.sensitive:
        lines.append("Possible sensitive data in PR body (types only): " + ", ".join(result.sensitive))
    if not result.branch_ok:
        lines.append("Warning: branch name should be <feat|fix|chore|docs|refactor|test|hotfix>/<issue#>-<slug>.")
    return lines


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event", required=True, help="path to the GitHub event JSON")
    args = parser.parse_args(argv)
    pull_request = json.loads(Path(args.event).read_text(encoding="utf-8"))["pull_request"]
    result = evaluate(pull_request.get("body") or "", pull_request["head"]["ref"])
    for line in describe(result):
        print(line)
    return 0 if result.ok else 1


if __name__ == "__main__":
    sys.exit(main())
