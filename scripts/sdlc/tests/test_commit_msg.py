"""Tests for scripts.sdlc.commit_msg."""
import contextlib
import io
import tempfile
import unittest
from pathlib import Path

from scripts.sdlc import commit_msg


class TestCheck(unittest.TestCase):
    def test_passes(self):
        for msg in [
            "feat: add thing", "fix(auth): handle 401", "chore!: drop api", "docs(sdlc): x\n\nbody",
            "perf: faster", "revert: undo", "build: x", "ci: x", "style: x", "test: x", "refactor: x",
            "Update login #12", "#12 tidy up", "Merge branch 'a' into b", "Merge pull request #1 from x/y",
            'Revert "feat: x"', "fixup! feat: x", "squash! fix: y",
        ]:
            self.assertIsNone(commit_msg.check(msg), msg)

    def test_fails(self):
        for msg in ["update stuff", "feature: x", "feat add", "feat:no space", "", "   \n", "WIP"]:
            self.assertIsNotNone(commit_msg.check(msg), msg)

    def test_issue_ref_only_on_first_line(self):
        self.assertIsNotNone(commit_msg.check("update stuff\n\ncloses #12"))


class TestCli(unittest.TestCase):
    def run_main(self, text):
        with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as handle:
            handle.write(text)
        self.addCleanup(Path(handle.name).unlink)
        out = io.StringIO()
        with contextlib.redirect_stderr(out), contextlib.redirect_stdout(out):
            code = commit_msg.main([handle.name])
        return code, out.getvalue()

    def test_ok(self):
        self.assertEqual(self.run_main("fix: x\n"), (0, ""))

    def test_bad(self):
        code, out = self.run_main("nope\n")
        self.assertEqual(code, 1)
        self.assertTrue(out.strip())


if __name__ == "__main__":
    unittest.main()
