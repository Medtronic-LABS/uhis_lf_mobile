"""Tests for scripts.sdlc.guard_staged."""
import contextlib
import io
import subprocess
import tempfile
import unittest
from pathlib import Path

from scripts.sdlc import guard_staged

PHONE = "0171" + "2345678"
TOKEN = "hf_" + "k" * 34


def reader(files):
    def read(path):
        value = files[path]
        if isinstance(value, Exception):
            raise value
        return value
    return read


class TestCheck(unittest.TestCase):
    def test_clean(self):
        self.assertEqual(guard_staged.check(["a.dart"], reader({"a.dart": "void main() {}"})), [])

    def test_protected_path_reported_without_reading(self):
        def explode(path):
            raise AssertionError("must not read protected files")
        problems = guard_staged.check(["env.production.json", "android/key.properties"], explode)
        self.assertEqual(
            problems, ["env.production.json: protected_path", "android/key.properties: protected_path"]
        )

    def test_credential_categories_reported_no_values(self):
        problems = guard_staged.check(["notes.md"], reader({"notes.md": f"key {TOKEN}"}))
        self.assertEqual(problems, ["notes.md: hf_token"])
        self.assertFalse(any(TOKEN in p for p in problems))

    def test_phi_categories_not_checked_in_source(self):
        text = f"phone {PHONE} mail jane@clinic.org NID 1234567890 id 12345678901234567"
        self.assertEqual(guard_staged.check(["a.dart"], reader({"a.dart": text})), [])

    def test_skips_sdlc_test_fixtures(self):
        path = "scripts/sdlc/tests/test_x.py"
        self.assertEqual(guard_staged.check([path], reader({path: TOKEN})), [])

    def test_skips_binary_unreadable_and_oversize(self):
        files = {
            "img.png": UnicodeDecodeError("utf-8", b"", 0, 1, "bad"),
            "gone.txt": OSError("missing"),
            "big.txt": TOKEN + "x" * 1_000_001,
        }
        self.assertEqual(guard_staged.check(list(files), reader(files)), [])


class TestDecodeBlob(unittest.TestCase):
    def test_text(self):
        self.assertEqual(guard_staged.decode_blob(b"hello"), "hello")

    def test_binary_and_large_read_as_empty(self):
        self.assertEqual(guard_staged.decode_blob(b"ab\x00cd"), "")
        self.assertEqual(guard_staged.decode_blob(b"x" * 1_000_001), "")


class TestUnreadableNote(unittest.TestCase):
    def test_unreadable_path_noted_on_stderr_path_only(self):
        err = io.StringIO()
        files = {"a.dart": OSError("boom secret-detail")}
        with contextlib.redirect_stderr(err):
            problems = guard_staged.check(["a.dart"], reader(files))
        self.assertEqual(problems, [])
        self.assertEqual(err.getvalue().strip(), "lw-guard: could not read staged a.dart; skipped")


class TestReadStagedBlob(unittest.TestCase):
    def git(self, repo, *args):
        subprocess.run(["git", "-C", repo, *args], check=True, capture_output=True)

    def test_reads_index_not_working_tree(self):
        with tempfile.TemporaryDirectory() as repo:
            self.git(repo, "init", "-q")
            target = Path(repo, "a.txt")
            target.write_text("staged " + TOKEN)
            self.git(repo, "add", "a.txt")
            target.write_text("clean working tree")
            staged = guard_staged.read_staged_blob("a.txt", repo)
            self.assertIn(TOKEN, staged)
            self.assertEqual(guard_staged.check(["a.txt"], lambda p: guard_staged.read_staged_blob(p, repo)),
                             ["a.txt: hf_token"])

    def test_unstaged_path_raises_oserror(self):
        with tempfile.TemporaryDirectory() as repo:
            self.git(repo, "init", "-q")
            with self.assertRaises(OSError):
                guard_staged.read_staged_blob("missing.txt", repo)


if __name__ == "__main__":
    unittest.main()
