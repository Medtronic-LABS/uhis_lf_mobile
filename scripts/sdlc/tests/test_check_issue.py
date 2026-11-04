"""Tests for scripts.sdlc.check_issue."""
import contextlib
import io
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from scripts.sdlc import check_issue
from scripts.sdlc.patterns import REQUIRED_SECTIONS

REPO_ROOT = Path(__file__).resolve().parents[3]
TICKED = "- [x] No patient data or secrets included"
UNTICKED = "- [ ] No patient data or secrets included"


def make_body(issue_type: str, overrides: dict | None = None, privacy: str = TICKED) -> str:
    values = {h: "something useful" for h in REQUIRED_SECTIONS[issue_type]}
    if "Privacy check" in values:
        values["Privacy check"] = privacy
    values.update(overrides or {})
    return "\n\n".join(f"### {h}\n\n{v}" for h, v in values.items())


class TestEvaluate(unittest.TestCase):
    def test_complete_bug_ok(self):
        result = check_issue.evaluate("t", make_body("bug"), ["bug"])
        self.assertTrue(result.ok)
        self.assertEqual(result.issue_type, "bug")
        self.assertEqual(result.missing, [])

    def test_each_type_complete_ok(self):
        for label, issue_type in (("enhancement", "feature"), ("chore", "task"), ("release", "release")):
            result = check_issue.evaluate("t", make_body(issue_type), [label])
            self.assertTrue(result.ok, issue_type)

    def test_missing_and_no_response_headings(self):
        body = make_body("bug", {"Steps to reproduce": "_No response_", "Impact": "   "})
        body = body.replace("### Frequency\n\nsomething useful", "")
        result = check_issue.evaluate("t", body, ["bug"])
        self.assertFalse(result.ok)
        self.assertEqual(result.missing, ["Steps to reproduce", "Frequency", "Impact"])

    def test_optional_headings_not_required(self):
        self.assertTrue(check_issue.evaluate("t", make_body("bug"), ["bug"]).ok)

    def test_privacy_unticked(self):
        result = check_issue.evaluate("t", make_body("task", privacy=UNTICKED), ["chore"])
        self.assertTrue(result.privacy_unchecked)
        self.assertFalse(result.ok)

    def test_privacy_upper_x(self):
        result = check_issue.evaluate("t", make_body("task", privacy="- [X] ok"), ["chore"])
        self.assertFalse(result.privacy_unchecked)

    def test_release_has_no_privacy_requirement(self):
        result = check_issue.evaluate("t", make_body("release"), ["release"])
        self.assertFalse(result.privacy_unchecked)

    def test_bearer_token_in_logs_flagged_not_echoed(self):
        secret = "abcdefghijklmnopqrstuvwxyz123456"
        body = make_body("bug") + "\n\n### Logs or screenshots\n\nD/Dio: Authorization: Bearer " + secret
        result = check_issue.evaluate("t", body, ["bug"])
        self.assertEqual(result.sensitive, ["bearer_token"])
        self.assertFalse(result.ok)
        self.assertNotIn(secret, check_issue.render_comment(result))

    def test_hf_token_flagged_not_echoed(self):
        secret = "hf_" + "q" * 34
        result = check_issue.evaluate("t", make_body("task", {"What": secret}), ["chore"])
        self.assertEqual(result.sensitive, ["hf_token"])
        self.assertNotIn(secret, check_issue.render_comment(result))

    def test_phone_flagged_version_not(self):
        phone = "0171" + "2345678"
        body = make_body("bug", {"App version": "1.1.0+15", "Impact": "call " + phone})
        result = check_issue.evaluate("t", body, ["bug"])
        self.assertEqual(result.sensitive, ["bd_phone"])

    def test_title_scanned(self):
        result = check_issue.evaluate("[Bug] 0171" + "2345678", make_body("bug"), ["bug"])
        self.assertEqual(result.sensitive, ["bd_phone"])

    def test_title_prefix_fallback(self):
        result = check_issue.evaluate("[Feature] thing", make_body("feature"), [])
        self.assertEqual(result.issue_type, "feature")

    def test_label_wins_over_title(self):
        result = check_issue.evaluate("[Bug] x", make_body("task"), ["chore"])
        self.assertEqual(result.issue_type, "task")

    def test_unknown_type_only_privacy_scan(self):
        clean = check_issue.evaluate("hello", "no headings here", ["question"])
        self.assertIsNone(clean.issue_type)
        self.assertTrue(clean.ok)
        dirty = check_issue.evaluate("hello", "ring 0171" + "2345678", [])
        self.assertFalse(dirty.ok)


class TestRenderComment(unittest.TestCase):
    def test_marker_and_content(self):
        body = make_body("bug", {"Impact": ""}, privacy=UNTICKED)
        comment = check_issue.render_comment(check_issue.evaluate("t", body, ["bug"]))
        self.assertTrue(comment.startswith("<!-- lw-issue-check -->"))
        self.assertIn("Impact", comment)
        self.assertIn("Privacy check", comment)
        self.assertIn("edit", comment.lower())

    def test_ok_comment_still_has_marker(self):
        comment = check_issue.render_comment(check_issue.evaluate("t", make_body("bug"), ["bug"]))
        self.assertTrue(comment.startswith("<!-- lw-issue-check -->"))

    def test_lists_sensitive_categories(self):
        result = check_issue.evaluate("t", "mail a.b@clinic.org", [])
        self.assertIn("email", check_issue.render_comment(result))


class TestCli(unittest.TestCase):
    def event(self, body, labels=("bug",), title="t"):
        return {"issue": {"title": title, "body": body, "labels": [{"name": n} for n in labels]}}

    def write_event(self, event: dict) -> str:
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
            json.dump(event, handle)
        self.addCleanup(Path(handle.name).unlink)
        return handle.name

    def run_main(self, event: dict) -> tuple[int, dict]:
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = check_issue.main(["--event", self.write_event(event)])
        return code, json.loads(out.getvalue())

    def test_ok_event(self):
        code, data = self.run_main(self.event(make_body("bug")))
        self.assertEqual(code, 0)
        self.assertTrue(data["ok"])
        self.assertIn("lw-issue-check", data["comment"])

    def test_null_body_event(self):
        code, data = self.run_main(self.event(None))
        self.assertEqual(code, 0)
        self.assertFalse(data["ok"])

    def test_both_invocation_forms(self):
        path = self.write_event(self.event(make_body("bug")))
        for cmd in (
            [sys.executable, "scripts/sdlc/check_issue.py", "--event", path],
            [sys.executable, "-m", "scripts.sdlc.check_issue", "--event", path],
        ):
            done = subprocess.run(cmd, cwd=REPO_ROOT, capture_output=True, text=True)
            self.assertEqual(done.returncode, 0, done.stderr)
            self.assertTrue(json.loads(done.stdout)["ok"])


if __name__ == "__main__":
    unittest.main()
