import re
import unittest
from pathlib import Path

from scripts.sdlc.patterns import REQUIRED_SECTIONS

ROOT = Path(__file__).resolve().parents[3]
GITHUB = ROOT / ".github"
FORMS = {"bug": "bug.yml", "feature": "feature.yml", "task": "task.yml", "release": "release.yml"}
FORM_LABELS = {"bug": "bug", "feature": "enhancement", "task": "chore", "release": "release"}
PRIVACY_OPTION = (
    "This issue contains no patient/member data, names, phone numbers, IDs, "
    "credentials, tokens or unscrubbed logs (this repo is public)"
)
EXPECTED_JOBS = {
    "ci.yml": {"sdlc-scripts", "secret-scan", "flutter"},
    "pr-check.yml": {"pr-check"},
    "android-apk.yml": {"build-apk"},
}


def read(rel):
    return (GITHUB / rel).read_text(encoding="utf-8")


def field_labels(text):
    """Field-level labels (under attributes:), not checkbox option labels."""
    return re.findall(r"^      label:\s*(.+?)\s*$", text, re.MULTILINE)


class IssueFormsTest(unittest.TestCase):
    def test_required_headings_are_field_labels(self):
        for issue_type, name in FORMS.items():
            labels = field_labels(read(f"ISSUE_TEMPLATE/{name}"))
            for heading in REQUIRED_SECTIONS[issue_type]:
                self.assertIn(heading, labels, f"{name} lacks field label {heading!r}")

    def test_every_field_has_id(self):
        for name in FORMS.values():
            text = read(f"ISSUE_TEMPLATE/{name}")
            ids = re.findall(r"^    id:\s*\S+", text, re.MULTILINE)
            self.assertEqual(len(ids), len(field_labels(text)), name)

    def test_privacy_checkbox_on_forms_that_require_it(self):
        for issue_type, name in FORMS.items():
            if "Privacy check" not in REQUIRED_SECTIONS[issue_type]:
                continue
            text = read(f"ISSUE_TEMPLATE/{name}")
            self.assertIn("type: checkboxes", text)
            self.assertIn(PRIVACY_OPTION, text)
            self.assertIn("required: true", text)

    def test_labels_and_title_prefix(self):
        for issue_type, name in FORMS.items():
            text = read(f"ISSUE_TEMPLATE/{name}")
            self.assertIn(f'labels: ["{FORM_LABELS[issue_type]}"]', text)
            self.assertIn(f'title: "[{issue_type.capitalize()}] "', text)

    def test_config_disables_blank_issues(self):
        text = read("ISSUE_TEMPLATE/config.yml")
        self.assertIn("blank_issues_enabled: false", text)
        self.assertIn("security/advisories/new", text)
        self.assertIn("docs/process/TICKETS.md", text)


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
                    "env:prod", "env:training", "env:dev", "status:needs-info",
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

    def test_issue_check_is_injection_safe(self):
        text = read("workflows/issue-check.yml")
        for block in re.findall(r"run: \|\n((?:[ ]{8,}.*\n|\n)+)", text):
            self.assertNotIn("${{", block)
        self.assertIn("issues: write", text)
        self.assertIn(".marker", text)
        self.assertIn(".needs_info_label", text)
        self.assertNotIn("lw-issue-check", text)
        self.assertNotIn("status:needs-info", text)
        self.assertNotIn("--force", text)

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
