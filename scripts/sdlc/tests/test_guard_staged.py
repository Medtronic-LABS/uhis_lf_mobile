"""Tests for scripts.sdlc.guard_staged."""
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

    def test_sensitive_categories_reported_no_values(self):
        files = {"notes.md": f"call {PHONE} key {TOKEN}"}
        problems = guard_staged.check(["notes.md"], reader(files))
        self.assertEqual(problems, ["notes.md: bd_phone", "notes.md: hf_token"])
        self.assertFalse(any(PHONE in p or TOKEN in p for p in problems))

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


class TestReadTextFile(unittest.TestCase):
    def test_skips_binary_and_large(self):
        with tempfile.TemporaryDirectory() as tmp:
            text, binary, big = Path(tmp, "t.txt"), Path(tmp, "b.bin"), Path(tmp, "big.txt")
            text.write_text("hello")
            binary.write_bytes(b"ab\x00cd")
            big.write_text("x" * 1_000_001)
            self.assertEqual(guard_staged.read_text_file(str(text)), "hello")
            self.assertEqual(guard_staged.read_text_file(str(binary)), "")
            self.assertEqual(guard_staged.read_text_file(str(big)), "")


if __name__ == "__main__":
    unittest.main()
