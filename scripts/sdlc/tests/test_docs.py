"""Checks for the process docs (docs/process/), CLAUDE.md pointer and repo hygiene."""
import re
import subprocess
import unittest
from pathlib import Path

from scripts.sdlc.patterns import find_sensitive

ROOT = Path(__file__).resolve().parents[3]
PROCESS = ROOT / "docs" / "process"
DOCS = ("SDLC.md", "TICKETS.md", "CLAUDE_ADMIN_SETUP.md", "JIRA_RETIREMENT.md")
JIRA_KEY_RE = re.compile(r"LEAP-\d")
GITIGNORE_RULES = (".claude/worktrees/", "env.*.json", "!env.example.json", "dist/")
STATUS_FLOW = ("Triage", "Backlog", "Ready", "In progress", "In review", "QA", "Done")


def read(path):
    return path.read_text(encoding="utf-8")


def names_in(directory, pattern):
    return sorted(p.parent.name if p.name == "SKILL.md" else p.stem for p in directory.glob(pattern))


class ProcessDocsTest(unittest.TestCase):
    def test_docs_exist(self):
        for name in DOCS:
            self.assertTrue((PROCESS / name).is_file(), f"docs/process/{name} missing")

    def test_sdlc_mentions_every_skill_and_agent(self):
        sdlc = read(PROCESS / "SDLC.md")
        skills = names_in(ROOT / ".claude/skills", "*/SKILL.md")
        agents = names_in(ROOT / ".claude/agents", "*.md")
        self.assertTrue(skills and agents)
        for name in skills + agents:
            self.assertIn(name, sdlc, f"SDLC.md does not mention {name}")

    def test_sdlc_sections_referenced_by_skills_and_agents(self):
        sdlc = read(PROCESS / "SDLC.md")
        for phrase in ("Definition of Ready", "Definition of Done", "Branching", "CI gates",
                       "Hotfix", "RELEASE_PLAN.md", "scripts/setup_dev.sh", "gh auth refresh -s project",
                       ".superpowers/sdd/"):
            self.assertIn(phrase, sdlc)
        for size in ("| S |", "| M |", "| L |"):
            self.assertIn(size, sdlc)

    def test_sdlc_status_flow_in_order(self):
        sdlc = read(PROCESS / "SDLC.md")
        self.assertIn(" → ".join(STATUS_FLOW), sdlc)

    def test_sdlc_points_at_ci_budgets_without_copying_them(self):
        sdlc = read(PROCESS / "SDLC.md")
        self.assertIn(".github/workflows/ci.yml", sdlc)
        for var in ("ANALYZE_ERROR_BUDGET", "TEST_FAILURE_BUDGET"):
            self.assertIn(var, sdlc)
            self.assertNotRegex(sdlc, rf"{var}`?\s*[=:]\s*\d", f"SDLC.md copies the {var} value")

    def test_size_bands_match_spec(self):
        template = read(ROOT / ".github/pull_request_template.md")
        sdlc = read(PROCESS / "SDLC.md")
        for text in (template, sdlc):
            self.assertIn("50", text)
            self.assertIn("judged by nature, not line count", text)
            self.assertNotIn("400", text)

    def test_project_workflows_consistent(self):
        script = read(ROOT / "scripts/github/setup_project.sh")
        admin = read(PROCESS / "CLAUDE_ADMIN_SETUP.md")
        self.assertIn("is:issue", script)
        self.assertNotIn("is:issue,pr", script)
        for name in ("Item added to project", "Item closed", "Pull request merged",
                     "Item reopened", "Auto-add to project"):
            self.assertIn(name, script)
            self.assertIn(name, admin)

    def test_doc_lengths(self):
        self.assertLessEqual(len(read(PROCESS / "SDLC.md").splitlines()), 260)
        self.assertLessEqual(len(read(PROCESS / "TICKETS.md").splitlines()), 70)

    def test_tickets_guide_covers_intake(self):
        tickets = read(PROCESS / "TICKETS.md")
        for phrase in ("/lw-ticket", "file a bug", "public", "Triage", "screenshot", "issues/new/choose"):
            self.assertIn(phrase, tickets)

    def test_admin_setup_covers_owner_steps(self):
        admin = read(PROCESS / "CLAUDE_ADMIN_SETUP.md")
        for phrase in ("dist/skills/lw-ticket.zip", "scripts/github/package_skill.sh",
                       "https://api.githubcopilot.com/mcp/", "sync_labels.sh", "setup_project.sh",
                       "protect_branches.sh", "--apply", "private vulnerability reporting",
                       "settings.local.json"):
            self.assertIn(phrase.lower(), admin.lower())

    def test_jira_keys_only_in_retirement_note(self):
        new_files = [PROCESS / n for n in DOCS if n != "JIRA_RETIREMENT.md"]
        new_files += [ROOT / "CLAUDE.md", ROOT / "README.md"]
        for path in new_files:
            self.assertIsNone(JIRA_KEY_RE.search(read(path)), f"{path.name} contains a Jira key")
        retirement = read(PROCESS / "JIRA_RETIREMENT.md")
        self.assertIn("2026-11-04", retirement)
        self.assertIn("Migrated from LEAP-", retirement)

    def test_docs_have_no_sensitive_data(self):
        for name in DOCS:
            self.assertEqual(find_sensitive(read(PROCESS / name)), [], name)

    def test_claude_md_points_at_process(self):
        claude = read(ROOT / "CLAUDE.md")
        self.assertIn("## Process & ticketing", claude)
        self.assertLess(claude.index("## Process & ticketing"), claude.index("## Visit Architecture"))
        for phrase in ("docs/process/SDLC.md", "docs/process/TICKETS.md", "/lw-ticket", "Jira"):
            self.assertIn(phrase, claude)

    def test_readme_links_sdlc(self):
        self.assertIn("docs/process/SDLC.md", read(ROOT / "README.md"))


class RepoHygieneTest(unittest.TestCase):
    def test_gitignore_rules(self):
        lines = {line.strip() for line in read(ROOT / ".gitignore").splitlines()}
        for rule in GITIGNORE_RULES:
            self.assertIn(rule, lines)

    def test_no_tracked_worktrees(self):
        out = subprocess.run(["git", "ls-files", ".claude/worktrees"], cwd=ROOT,
                             capture_output=True, text=True, check=True).stdout
        self.assertEqual(out.strip(), "")


if __name__ == "__main__":
    unittest.main()
