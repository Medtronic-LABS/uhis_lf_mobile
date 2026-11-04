"""Validate a GitHub issue against the LEAPWELL intake contract.

CLI: python3 scripts/sdlc/check_issue.py --event "$GITHUB_EVENT_PATH"
Prints JSON {"ok": bool, "comment": str} and exits 0; the workflow decides labels.
"""
import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from scripts.sdlc.patterns import (  # noqa: E402
    PRIVACY_HEADING,
    REQUIRED_SECTIONS,
    TITLE_PREFIXES,
    TYPE_LABELS,
    find_sensitive,
)

COMMENT_MARKER = "<!-- lw-issue-check -->"
_HEADING_RE = re.compile(r"^###[ \t]+(.+?)[ \t]*$", re.MULTILINE)
_TICKED_RE = re.compile(r"-\s*\[[xX]\]")
_EMPTY_VALUES = {"", "_no response_"}


@dataclass
class IssueResult:
    issue_type: Optional[str]
    missing: list[str] = field(default_factory=list)
    privacy_unchecked: bool = False
    sensitive: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not (self.missing or self.privacy_unchecked or self.sensitive)


def parse_sections(body: str) -> dict[str, str]:
    """Split a Markdown issue body into {heading: content} for `### Heading` blocks."""
    matches = list(_HEADING_RE.finditer(body))
    sections: dict[str, str] = {}
    for index, match in enumerate(matches):
        end = matches[index + 1].start() if index + 1 < len(matches) else len(body)
        sections[match.group(1)] = body[match.end():end].strip()
    return sections


def detect_type(title: str, labels: list[str]) -> Optional[str]:
    for label, issue_type in TYPE_LABELS.items():
        if label in labels:
            return issue_type
    lowered = title.strip().lower()
    for prefix, issue_type in TITLE_PREFIXES.items():
        if lowered.startswith(prefix):
            return issue_type
    return None


def _is_empty(value: str) -> bool:
    return value.strip().lower() in _EMPTY_VALUES


def evaluate(title: str, body: str, labels: list[str]) -> IssueResult:
    """Check required sections, the privacy tick-box and sensitive data."""
    issue_type = detect_type(title, labels)
    result = IssueResult(issue_type=issue_type, sensitive=find_sensitive(f"{title}\n{body}"))
    if issue_type is None:
        return result
    sections = parse_sections(body)
    required = REQUIRED_SECTIONS[issue_type]
    result.missing = [h for h in required if _is_empty(sections.get(h, ""))]
    if PRIVACY_HEADING in required:
        result.privacy_unchecked = not _TICKED_RE.search(sections.get(PRIVACY_HEADING, ""))
    return result


def render_comment(result: IssueResult) -> str:
    """Bot comment text; lists headings and categories only, never matched values."""
    lines = [COMMENT_MARKER]
    if result.ok:
        lines.append("Intake check passed. Thanks for the complete report.")
        return "\n".join(lines)
    lines.append("This issue needs a few changes before it can be triaged. Please edit the issue description.")
    if result.missing:
        lines.append("\nMissing or empty sections:")
        lines.extend(f"- {heading}" for heading in result.missing)
    if result.privacy_unchecked:
        lines.append(f"\nThe **{PRIVACY_HEADING}** box is not ticked. Confirm no patient data or secrets are included.")
    if result.sensitive:
        lines.append(
            "\nPossible sensitive data detected (types only): "
            + ", ".join(result.sensitive)
            + ". This repository is public: remove it from the issue, then rotate any exposed credential."
        )
    return "\n".join(lines)


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--event", required=True, help="path to the GitHub event JSON")
    args = parser.parse_args(argv)
    issue = json.loads(Path(args.event).read_text(encoding="utf-8"))["issue"]
    labels = [label["name"] for label in issue.get("labels") or []]
    result = evaluate(issue.get("title") or "", issue.get("body") or "", labels)
    print(json.dumps({"ok": result.ok, "comment": render_comment(result)}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
