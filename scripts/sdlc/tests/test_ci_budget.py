import tempfile
import unittest
from pathlib import Path

from scripts.sdlc import ci_budget


class CountAnalyzerErrorsTest(unittest.TestCase):
    def test_counts_only_error_lines(self):
        text = (
            "  error • Undefined name 'x' • lib/a.dart:1:1 • undefined_identifier\n"
            "warning • Unused import • lib/b.dart:2:1 • unused_import\n"
            "   info • Prefer const • lib/c.dart:3:1 • prefer_const\n"
            "  error • Missing return • lib/d.dart:4:1 • missing_return\n"
            "4 issues found.\n"
        )
        self.assertEqual(ci_budget.count_analyzer_errors(text), 2)

    def test_no_errors(self):
        self.assertEqual(ci_budget.count_analyzer_errors("No issues found!\n"), 0)

    def test_real_summary_form(self):
        text = "  error • x • a • b\n236 issues found. (ran in 5.2s)\n"
        self.assertEqual(ci_budget.count_analyzer_errors(text), 1)

    def test_single_issue_summary(self):
        self.assertEqual(ci_budget.count_analyzer_errors("1 issue found.\n"), 0)

    def test_empty_output_is_none(self):
        self.assertIsNone(ci_budget.count_analyzer_errors(""))

    def test_garbage_output_is_none(self):
        self.assertIsNone(ci_budget.count_analyzer_errors("Unhandled exception: boom\n"))

    def test_errors_without_summary_is_none(self):
        self.assertIsNone(ci_budget.count_analyzer_errors("  error • x • a • b\n"))


class CountTestFailuresTest(unittest.TestCase):
    def test_failed_summary(self):
        text = "00:10 +1696 ~3 -38: Some tests failed.\n"
        self.assertEqual(ci_budget.count_test_failures(text), 38)

    def test_all_passed(self):
        self.assertEqual(ci_budget.count_test_failures("00:10 +1700: All tests passed!\n"), 0)

    def test_uses_last_progress_line(self):
        text = "00:01 +5 -1: a\n00:09 +20 -3: Some tests failed.\n"
        self.assertEqual(ci_budget.count_test_failures(text), 3)

    def test_unparseable_returns_none(self):
        self.assertIsNone(ci_budget.count_test_failures("compile error\n"))


class CliTest(unittest.TestCase):
    def _run(self, flag, content, budget):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "out.txt"
            path.write_text(content, encoding="utf-8")
            return ci_budget.main([flag, str(path), "--budget", str(budget)])

    SUMMARY = "1 issue found.\n"

    def test_analyze_within_budget(self):
        self.assertEqual(self._run("--analyze", "  error • x • a • b\n" + self.SUMMARY, 1), 0)

    def test_analyze_over_budget(self):
        self.assertEqual(self._run("--analyze", "  error • x • a • b\n" + self.SUMMARY, 0), 1)

    def test_analyze_empty_output_fails(self):
        self.assertEqual(self._run("--analyze", "", 40), 1)

    def test_tests_within_budget(self):
        self.assertEqual(self._run("--tests", "00:01 +5 -2: Some tests failed.\n", 2), 0)

    def test_tests_over_budget(self):
        self.assertEqual(self._run("--tests", "00:01 +5 -3: Some tests failed.\n", 2), 1)

    def test_tests_unparseable_fails(self):
        self.assertEqual(self._run("--tests", "boom\n", 38), 1)


if __name__ == "__main__":
    unittest.main()
