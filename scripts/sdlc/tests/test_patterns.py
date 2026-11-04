"""Tests for scripts.sdlc.patterns (sensitive-data scan, protected paths, issue refs)."""
import unittest

from scripts.sdlc.patterns import (
    ISSUE_REF_RE,
    REQUIRED_SECTIONS,
    TYPE_LABELS,
    find_sensitive,
    is_protected_path,
)


class TestFindSensitive(unittest.TestCase):
    def test_flags_bd_phone_both_forms(self):
        self.assertEqual(find_sensitive("call 01712345678"), ["bd_phone"])
        self.assertEqual(find_sensitive("call +880 1712-345678"), ["bd_phone"])

    def test_ignores_versions_dates_and_short_numbers(self):
        text = "LEAPWELL 1.1.0+15 on 2026-11-04, build 14, id 123456789, code 4821"
        self.assertEqual(find_sensitive(text), [])

    def test_ignores_epoch_millis(self):
        self.assertEqual(find_sensitive('"visitDate": 1750000000000'), [])

    def test_national_id_lengths(self):
        for digits in ("1234567890", "2234567890123", "12345678901234567"):
            self.assertEqual(find_sensitive("NID " + digits), ["national_id"], digits)

    def test_email(self):
        self.assertEqual(find_sensitive("mail jane.doe@clinic.org now"), ["email"])

    def test_placeholder_emails_ignored(self):
        self.assertEqual(find_sensitive("a@example.com noreply@anthropic.com"), [])

    def test_bearer_category_only(self):
        text = "Authorization: Bearer " + "abcdefghijklmnopqrstuvwxyz123456"
        self.assertEqual(find_sensitive(text), ["bearer_token"])

    def test_hf_token(self):
        self.assertEqual(find_sensitive("key " + "hf_" + "a" * 34), ["hf_token"])

    def test_github_token(self):
        self.assertEqual(find_sensitive("t " + "ghp_" + "A1" * 18), ["github_token"])
        self.assertEqual(find_sensitive("t " + "github_pat_" + "b" * 30), ["github_token"])

    def test_google_api_key(self):
        self.assertEqual(find_sensitive("k " + "AIza" + "x" * 35), ["google_api_key"])

    def test_private_key(self):
        self.assertEqual(
            find_sensitive("-----BEGIN " + "RSA PRIVATE KEY-----"), ["private_key"]
        )

    def test_jwt(self):
        jwt = "eyJ" + "a" * 10 + ".eyJ" + "b" * 10 + "." + "c" * 10
        self.assertEqual(find_sensitive("token=" + jwt), ["jwt"])

    def test_password_assignment_forms(self):
        for text in ("password=hunter2abc", 'password: "Sup3rSecret"', '"password": "abc12345"'):
            self.assertEqual(find_sensitive(text), ["password_assignment"], text)

    def test_password_label_strings_not_flagged(self):
        self.assertEqual(find_sensitive("static const password = 'Password';"), [])
        self.assertEqual(find_sensitive("password: <redacted>"), [])
        self.assertEqual(find_sensitive("passwordHashKey = widget.key"), [])

    def test_sorted_unique_multiple(self):
        text = "01712345678 and 01812345678 and a@clinic.org"
        self.assertEqual(find_sensitive(text), ["bd_phone", "email"])

    def test_empty(self):
        self.assertEqual(find_sensitive(""), [])


class TestProtectedPath(unittest.TestCase):
    def test_protected(self):
        for path in (
            "env.production.json", "env.development.json", "env.json",
            "android/key.properties", "release.jks", "a/b/upload.keystore",
            "android/app/google-services.json", "ios/Runner/GoogleService-Info.plist",
            ".env", ".env.local", "sub/.env.production",
        ):
            self.assertTrue(is_protected_path(path), path)

    def test_not_protected(self):
        for path in (
            "env.example.json", "pubspec.yaml", "lib/environment.dart",
            "lib/env_config.dart", "docs/env.md", "key_properties.md",
        ):
            self.assertFalse(is_protected_path(path), path)


class TestIssueRef(unittest.TestCase):
    def test_matches(self):
        for text in ("closes #12", "Refs #7", "Fixes #3", "resolved #9", "Close #1"):
            self.assertIsNotNone(ISSUE_REF_RE.search(text), text)

    def test_rejects(self):
        for text in ("see #12", "#12", "LEAP-12", "closes 12", "prefix#4"):
            self.assertIsNone(ISSUE_REF_RE.search(text), text)


class TestContractTables(unittest.TestCase):
    def test_required_sections(self):
        self.assertEqual(REQUIRED_SECTIONS["release"], ["Version", "Release checklist"])
        self.assertEqual(REQUIRED_SECTIONS["task"][-1], "Privacy check")
        self.assertEqual(len(REQUIRED_SECTIONS["bug"]), 10)
        self.assertEqual(len(REQUIRED_SECTIONS["feature"]), 7)

    def test_type_labels(self):
        self.assertEqual(
            TYPE_LABELS,
            {"bug": "bug", "enhancement": "feature", "chore": "task", "release": "release"},
        )


if __name__ == "__main__":
    unittest.main()
