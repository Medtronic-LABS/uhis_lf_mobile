"""Structure checks for the committed Claude toolkit (.claude/) and git hooks."""
import json
import os
import re
import unittest
from pathlib import Path

from scripts.sdlc.check_issue import evaluate
from scripts.sdlc.patterns import PRIVACY_HEADING, REQUIRED_SECTIONS, TYPE_LABELS, find_sensitive

ROOT = Path(__file__).resolve().parents[3]
CLAUDE = ROOT / ".claude"
AGENTS_DIR = CLAUDE / "agents"
SKILLS_DIR = CLAUDE / "skills"
TICKET_DIR = SKILLS_DIR / "lw-ticket"
GITHOOKS = ROOT / ".githooks"
FORMS_DIR = ROOT / ".github" / "ISSUE_TEMPLATE"

HOOK_COMMAND = 'python3 "$CLAUDE_PROJECT_DIR"/scripts/sdlc/guard_tool.py'
AGENTS = {
    "lw-architect": ("opus", {"Read", "Grep", "Glob", "Bash"}),
    "lw-implementer": ("sonnet", {"Read", "Grep", "Glob", "Bash", "Edit", "Write"}),
    "lw-reviewer": ("opus", {"Read", "Grep", "Glob", "Bash"}),
    "lw-qa": ("sonnet", {"Read", "Grep", "Glob", "Bash", "Write", "Edit"}),
    "lw-security": ("opus", {"Read", "Grep", "Glob", "Bash"}),
    "lw-release": ("sonnet", {"Read", "Grep", "Glob", "Bash"}),
}
READ_ONLY_AGENTS = {"lw-architect", "lw-reviewer", "lw-security", "lw-release"}
WORKFLOW_SKILLS = {"lw-start", "lw-feature", "lw-fix", "lw-pr", "lw-release"}
TICKET_TYPES = ("bug", "feature", "task", "release")
HARD_LIMIT_PHRASES = ("never merge", "never set priority", "prod", "secret")
MAX_TICKET_SKILL_LINES = 220


def frontmatter(path):
    """Return ({key: value}, body) for a file that starts with a `---` block."""
    text = path.read_text(encoding="utf-8")
    if not text.startswith("---\n"):
        raise AssertionError(f"{path} does not start with ---")
    end = text.index("\n---\n", 4)
    meta = {}
    for line in text[4:end].splitlines():
        key, sep, value = line.partition(":")
        if sep and not line.startswith(" "):
            meta[key.strip()] = value.strip()
    return meta, text[end + 5:]


def form_options(name):
    """Dropdown options of an issue form, keyed by field label."""
    text = (FORMS_DIR / f"{name}.yml").read_text(encoding="utf-8")
    options = {}
    for block in re.split(r"^  - type: ", text, flags=re.MULTILINE)[1:]:
        if not block.startswith("dropdown"):
            continue
        label = re.search(r"^      label:\s*(.+?)\s*$", block, re.MULTILINE).group(1)
        options[label] = re.findall(r"^        - (.+?)\s*$", block, re.MULTILINE)
    return options


def toolkit_files():
    files = list(AGENTS_DIR.glob("*.md")) + list(SKILLS_DIR.rglob("*.md"))
    files += [CLAUDE / "settings.json", ROOT / "scripts" / "setup_dev.sh"]
    files += [p for p in GITHOOKS.iterdir() if p.is_file()]
    return files


class SettingsTest(unittest.TestCase):
    def test_hooks_only_with_guard_tool(self):
        settings = json.loads((CLAUDE / "settings.json").read_text(encoding="utf-8"))
        self.assertEqual(set(settings), {"hooks"})
        self.assertEqual(set(settings["hooks"]), {"PreToolUse"})
        [entry] = settings["hooks"]["PreToolUse"]
        self.assertEqual(entry["matcher"], "Bash|Read|Edit|Write")
        [hook] = entry["hooks"]
        self.assertEqual(hook, {"type": "command", "command": HOOK_COMMAND, "timeout": 10})


class AgentsTest(unittest.TestCase):
    def test_exact_agent_set(self):
        self.assertEqual({p.stem for p in AGENTS_DIR.glob("*.md")}, set(AGENTS))

    def test_frontmatter(self):
        for name, (model, tools) in AGENTS.items():
            meta, _ = frontmatter(AGENTS_DIR / f"{name}.md")
            self.assertEqual(meta.get("name"), name)
            self.assertTrue(meta.get("description"), name)
            self.assertEqual(meta.get("model"), model, name)
            declared = {t.strip() for t in meta.get("tools", "").split(",")}
            self.assertTrue(tools <= declared, f"{name} tools {declared}")
            if name in READ_ONLY_AGENTS:
                self.assertFalse({"Edit", "Write"} & declared, f"{name} must be read-only")

    def test_hard_limits_stated(self):
        for name in AGENTS:
            _, body = frontmatter(AGENTS_DIR / f"{name}.md")
            lowered = body.lower()
            self.assertIn("## hard limits", lowered, name)
            for phrase in HARD_LIMIT_PHRASES:
                self.assertIn(phrase, lowered, f"{name} lacks {phrase!r}")

    def test_reviewer_gives_two_verdicts(self):
        _, body = frontmatter(AGENTS_DIR / "lw-reviewer.md")
        for verdict in ("Spec ✅", "Spec ❌", "Approved", "Changes requested", "Engineering Design Standards"):
            self.assertIn(verdict, body)


class SkillsTest(unittest.TestCase):
    def test_exact_skill_set(self):
        self.assertEqual({p.parent.name for p in SKILLS_DIR.glob("*/SKILL.md")}, WORKFLOW_SKILLS | {"lw-ticket"})

    def test_frontmatter(self):
        for skill in WORKFLOW_SKILLS | {"lw-ticket"}:
            meta, body = frontmatter(SKILLS_DIR / skill / "SKILL.md")
            self.assertEqual(meta.get("name"), skill)
            self.assertTrue(meta.get("description"), skill)
            self.assertTrue(body.strip(), skill)

    def test_workflow_skills_are_manual_only(self):
        for skill in WORKFLOW_SKILLS:
            meta, _ = frontmatter(SKILLS_DIR / skill / "SKILL.md")
            self.assertEqual(meta.get("disable-model-invocation"), "true", skill)


class TicketSkillTest(unittest.TestCase):
    def setUp(self):
        self.meta, self.body = frontmatter(TICKET_DIR / "SKILL.md")

    def test_chat_safe_frontmatter(self):
        self.assertEqual(set(self.meta), {"name", "description"})
        for trigger in ("bug", "ticket", "issue", "feature request", "task"):
            self.assertIn(trigger, self.meta["description"].lower())

    def test_focused_length(self):
        lines = (TICKET_DIR / "SKILL.md").read_text(encoding="utf-8").count("\n")
        self.assertLessEqual(lines, MAX_TICKET_SKILL_LINES)

    def test_self_contained(self):
        for path in TICKET_DIR.rglob("*.md"):
            text = path.read_text(encoding="utf-8")
            self.assertNotIn("../", text, f"{path} reaches outside the skill folder")
        for ref in re.findall(r"references/[\w-]+\.md", self.body):
            self.assertTrue((TICKET_DIR / ref).is_file(), ref)
        for issue_type in TICKET_TYPES:
            self.assertIn(f"references/{issue_type}.md", self.body)
        self.assertIn("references/privacy.md", self.body)

    def test_flow_essentials(self):
        for needle in (
            "gh issue list", "--body-file", "gh project item-add 4 --owner Medtronic-LABS",
            "issue_write", "issues/new?template=",
            "https://github.com/Medtronic-LABS/uhis_lf_mobile/security/advisories/new",
            "AskUserQuestion", "adb devices", "prio:", "env:", "area:",
        ):
            self.assertIn(needle, self.body)

    def test_references_carry_contract_headings(self):
        for issue_type in TICKET_TYPES:
            text = (TICKET_DIR / "references" / f"{issue_type}.md").read_text(encoding="utf-8")
            for heading in REQUIRED_SECTIONS[issue_type]:
                self.assertRegex(text, rf"(?m)^### {re.escape(heading)}$", f"{issue_type}: {heading}")

    def test_body_templates_pass_issue_check(self):
        type_label = {issue_type: label for label, issue_type in TYPE_LABELS.items()}
        for issue_type in TICKET_TYPES:
            text = (TICKET_DIR / "references" / f"{issue_type}.md").read_text(encoding="utf-8")
            body = re.search(r"```markdown\n(.*?)```", text, re.DOTALL).group(1)
            result = evaluate(f"[{issue_type}] summary", body, [type_label[issue_type]])
            self.assertTrue(result.ok, f"{issue_type}: {result}")

    def test_privacy_section_template_is_ticked(self):
        for issue_type in TICKET_TYPES:
            if PRIVACY_HEADING not in REQUIRED_SECTIONS[issue_type]:
                continue
            text = (TICKET_DIR / "references" / f"{issue_type}.md").read_text(encoding="utf-8")
            self.assertIn("- [x] This issue contains no patient/member data", text, issue_type)

    def test_references_offer_form_dropdown_options(self):
        for issue_type in TICKET_TYPES:
            text = (TICKET_DIR / "references" / f"{issue_type}.md").read_text(encoding="utf-8")
            for label, options in form_options(issue_type).items():
                for option in options:
                    self.assertIn(option, text, f"{issue_type}/{label}: {option}")

    def test_privacy_reference_covers_categories(self):
        text = (TICKET_DIR / "references" / "privacy.md").read_text(encoding="utf-8").lower()
        for needle in ("phone", "nid", "email", "gps", "token", "password", "logcat", "<member-id>", "screenshot"):
            self.assertIn(needle, text)


class GitHooksTest(unittest.TestCase):
    EXPECTED = {
        "commit-msg": 'python3 scripts/sdlc/commit_msg.py "$1"',
        "pre-commit": "python3 scripts/sdlc/guard_staged.py",
    }

    def test_hooks_executable_posix_sh(self):
        for name, call in self.EXPECTED.items():
            path = GITHOOKS / name
            self.assertTrue(os.access(path, os.X_OK), f"{name} not executable")
            text = path.read_text(encoding="utf-8")
            self.assertTrue(text.startswith("#!/bin/sh\n"), name)
            self.assertIn('cd "$(git rev-parse --show-toplevel)"', text)
            self.assertIn(call, text)

    def test_setup_dev_script(self):
        path = ROOT / "scripts" / "setup_dev.sh"
        self.assertTrue(os.access(path, os.X_OK))
        text = path.read_text(encoding="utf-8")
        self.assertIn("git config core.hooksPath .githooks", text)
        self.assertIn("gh auth status", text)


class ToolkitPrivacyTest(unittest.TestCase):
    def test_no_sensitive_values_committed(self):
        for path in toolkit_files():
            found = find_sensitive(path.read_text(encoding="utf-8"))
            self.assertEqual(found, [], f"{path.relative_to(ROOT)}: {found}")


if __name__ == "__main__":
    unittest.main()
