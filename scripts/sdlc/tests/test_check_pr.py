"""Tests for scripts.sdlc.check_pr."""
import contextlib
import io
import json
import tempfile
import unittest
from pathlib import Path

from scripts.sdlc import check_pr


class TestEvaluate(unittest.TestCase):
    def test_issue_ref_forms_pass(self):
        for body in ("closes #12", "Refs #7", "Fixes #3\n\nmore"):
            self.assertTrue(check_pr.evaluate(body, "feat/12-x").ok, body)

    def test_missing_ref_fails(self):
        for body in ("#12", "LEAP-12", "", "see #4"):
            result = check_pr.evaluate(body, "feat/12-x")
            self.assertFalse(result.has_issue_ref, body)
            self.assertFalse(result.ok, body)

    def test_branch_is_warning_only(self):
        result = check_pr.evaluate("closes #1", "my-random-branch")
        self.assertFalse(result.branch_ok)
        self.assertTrue(result.ok)

    def test_branch_forms(self):
        for ref in ("feat/12-x", "fix/3-a-b", "chore/1-x", "docs/2-x", "refactor/4-x", "test/5-x", "hotfix/6-x"):
            self.assertTrue(check_pr.evaluate("refs #1", ref).branch_ok, ref)
        for ref in ("feat/x", "feature/12-x", "main", "feat/12"):
            self.assertFalse(check_pr.evaluate("refs #1", ref).branch_ok, ref)

    def test_sensitive_fails(self):
        result = check_pr.evaluate("closes #1 call 0171" + "2345678", "feat/1-x")
        self.assertEqual(result.sensitive, ["bd_phone"])
        self.assertFalse(result.ok)


class TestCli(unittest.TestCase):
    def run_main(self, body, ref="feat/1-x"):
        event = {"pull_request": {"body": body, "head": {"ref": ref}}}
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as handle:
            json.dump(event, handle)
        self.addCleanup(Path(handle.name).unlink)
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = check_pr.main(["--event", handle.name])
        return code, out.getvalue()

    def test_pass(self):
        self.assertEqual(self.run_main("closes #1")[0], 0)

    def test_fail_null_body(self):
        code, out = self.run_main(None)
        self.assertEqual(code, 1)
        self.assertIn("issue", out.lower())

    def test_fail_does_not_echo_value(self):
        token = "hf_" + "z" * 34
        code, out = self.run_main("closes #1 " + token)
        self.assertEqual(code, 1)
        self.assertIn("hf_token", out)
        self.assertNotIn(token, out)


if __name__ == "__main__":
    unittest.main()
