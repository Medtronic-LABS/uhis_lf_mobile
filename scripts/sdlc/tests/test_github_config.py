import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GITHUB = ROOT / ".github"
EXPECTED_JOBS = {
    "ci.yml": {"sdlc-scripts", "secret-scan", "flutter"},
    "pr-check.yml": {"pr-check"},
    "android-apk.yml": {"build-apk"},
}


def read(rel):
    return (GITHUB / rel).read_text(encoding="utf-8")


class IssueChooserTest(unittest.TestCase):
    def test_config_points_at_leapwell(self):
        text = read("ISSUE_TEMPLATE/config.yml")
        self.assertIn("blank_issues_enabled: true", text)
        self.assertIn("security/advisories/new", text)
        self.assertIn("File bugs, features and tasks in leapwell", text)
        self.assertIn("https://github.com/Medtronic-LABS/leapwell/issues/new/choose", text)
        self.assertIn("https://github.com/Medtronic-LABS/leapwell/discussions", text)

    def test_no_issue_forms_or_issue_check_remain(self):
        forms = sorted(p.name for p in (GITHUB / "ISSUE_TEMPLATE").iterdir())
        self.assertEqual(forms, ["config.yml"])
        self.assertFalse((GITHUB / "workflows" / "issue-check.yml").exists())


class RepoFilesTest(unittest.TestCase):
    def test_pr_template(self):
        text = read("pull_request_template.md")
        for needle in ("Closes #", "## Summary", "Size", "Test evidence", "Screenshots",
                       "Risk & rollback"):
            self.assertIn(needle, text)

    def test_codeowners(self):
        text = read("CODEOWNERS")
        self.assertIn("* @Medtronic-LABS/leapfrogging", text)
        for path in ("/.github/", "/lib/core/auth/", "/lib/core/db/",
                     "/lib/core/api/endpoints.dart", "/android/", "/pubspec.yaml",
                     "/scripts/release.sh", "/.claude/", "/scripts/sdlc/"):
            self.assertRegex(text, rf"(?m)^{re.escape(path)}\s+@amreshyadavgit @adityab24840")

    def test_labels(self):
        text = read("labels.yml")
        names = re.findall(r"^- name:\s*(.+?)\s*$", text, re.MULTILINE)
        names = [n.strip("\"'") for n in names]
        self.assertEqual(len(names), len(set(names)))
        required = {"bug", "documentation", "duplicate", "enhancement", "good first issue",
                    "help wanted", "invalid", "question", "wontfix", "refactor", "tech-debt",
                    "chore", "release", "prio:P0", "prio:P1", "prio:P2", "prio:P3",
                    "env:prod", "env:training", "env:dev",
                    "status:blocked", "status:needs-design"}
        required |= {f"area:{a}" for a in (
            "auth sync db visit cdss scribe coaching teleconsult household push "
            "release ci i18n").split()}
        self.assertLessEqual(required, set(names))
        self.assertRegex(text, r"- name: bug\n  color: \"?d73a4a")


class WorkflowsTest(unittest.TestCase):
    def test_job_ids(self):
        for name, jobs in EXPECTED_JOBS.items():
            after_jobs = read(f"workflows/{name}").split("\njobs:", 1)[1]
            found = set(re.findall(r"^  ([\w-]+):\s*$", after_jobs, re.MULTILINE))
            self.assertEqual(found, jobs, name)

    def test_ci_has_budgets(self):
        text = read("workflows/ci.yml")
        self.assertIn("ANALYZE_ERROR_BUDGET: 40", text)
        self.assertIn("TEST_FAILURE_BUDGET: 38", text)
        self.assertIn("fetch-depth: 0", text)
        self.assertIn("ci_budget.py", text)

    def test_android_apk_no_longer_runs_analyze_or_tests(self):
        text = read("workflows/android-apk.yml")
        self.assertIn("\npermissions:\n  contents: read\n", text)
        self.assertNotIn("flutter analyze", text)
        self.assertNotIn("flutter test", text)
        self.assertEqual(text.count("- develop"), 2)


if __name__ == "__main__":
    unittest.main()
