"""Tests for scripts/github/*.sh: dry-run by default, never call gh."""
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GH_DIR = ROOT / "scripts" / "github"
MUTATING = ["sync_labels.sh", "setup_project.sh", "protect_branches.sh"]
ALL = MUTATING


class AdminScriptsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.calls = Path(cls.tmp.name) / "gh_calls.log"
        fake = Path(cls.tmp.name) / "gh"
        fake.write_text(f'#!/bin/sh\necho "$@" >> "{cls.calls}"\nexit 99\n')
        fake.chmod(fake.stat().st_mode | stat.S_IXUSR)
        cls.env = dict(os.environ, PATH=f"{cls.tmp.name}:{os.environ['PATH']}")

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def run_script(self, name, *args):
        return subprocess.run(
            ["bash", str(GH_DIR / name), *args],
            capture_output=True, text=True, env=self.env, cwd=ROOT,
        )

    def test_scripts_exist_and_executable(self):
        for name in ALL + ["lib.sh"]:
            self.assertTrue((GH_DIR / name).is_file(), name)
        for name in ALL:
            self.assertTrue(os.access(GH_DIR / name, os.X_OK), name)

    def test_help_exits_zero(self):
        for name in ALL:
            r = self.run_script(name, "--help")
            self.assertEqual(r.returncode, 0, name + r.stderr)
            self.assertIn("Usage", r.stdout)

    def test_dry_run_prints_gh_and_never_calls_it(self):
        for name in MUTATING:
            r = self.run_script(name)
            self.assertEqual(r.returncode, 0, name + r.stderr)
            self.assertIn("[dry-run] gh", r.stdout, name)
        self.assertFalse(self.calls.exists(), "gh was invoked during dry-run")

    def test_labels_dry_run_covers_every_label(self):
        out = self.run_script("sync_labels.sh").stdout
        self.assertIn("gh label create bug --color d73a4a", out)
        self.assertIn("--force", out)
        self.assertIn("good\\ first\\ issue", out)
        self.assertIn("Blocked\\ by\\ another\\ item", out)

    def test_protection_values(self):
        out = self.run_script("protect_branches.sh").stdout
        for check in ["pr-check", "sdlc-scripts", "secret-scan", "flutter", "build-apk"]:
            self.assertIn(f'"{check}"', out)
        self.assertIn("branches/main/protection", out)
        self.assertIn("branches/develop/protection", out)
        self.assertIn('"required_approving_review_count": 2', out)
        self.assertIn('"required_approving_review_count": 1', out)
        self.assertIn('"enforce_admins": false', out)
        self.assertIn('"allow_force_pushes": false', out)

    def test_project_dry_run_content(self):
        out = self.run_script("setup_project.sh").stdout
        for word in ["P0", "P1", "P2", "P3", "Triage", "QA", "Sprint", "Settings"]:
            self.assertIn(word, out)
        self.assertIn("Backlog", out)
        self.assertIn("In review", out)

    def test_project_never_mutates_status(self):
        out = self.run_script("setup_project.sh").stdout
        self.assertEqual(out.count("updateProjectV2Field"), 1)  # Priority only
        self.assertNotIn("status-reset", out)
        self.assertIn("UI", out)


if __name__ == "__main__":
    unittest.main()
