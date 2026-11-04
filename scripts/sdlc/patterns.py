"""Shared patterns and contract tables for the LEAPWELL SDLC checks.

Single home for: the sensitive-data scan, protected file paths, the issue
reference rule and the required issue sections. Only category names are ever
returned for sensitive matches, never the matched text.
"""
import re

_PLACEHOLDER_EMAIL_DOMAINS = re.compile(r"^example\.(com|org|net)$", re.IGNORECASE)
_PLACEHOLDER_EMAIL_LOCALS = re.compile(r"^(no-?reply)$", re.IGNORECASE)
_EMAIL_RE = re.compile(r"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}")


def _real_email_present(text: str) -> bool:
    for match in _EMAIL_RE.finditer(text):
        local, _, domain = match.group().rpartition("@")
        if not (_PLACEHOLDER_EMAIL_DOMAINS.match(domain) or _PLACEHOLDER_EMAIL_LOCALS.match(local)):
            return True
    return False


# category -> compiled regex. Email is handled separately (placeholder filter).
_PATTERNS: dict[str, re.Pattern[str]] = {
    "bd_phone": re.compile(r"(?<![\w.])(?:\+?880[\s-]?|0)1[3-9]\d{2}[\s-]?\d{6}(?!\d)"),
    # 10 / 13 / 17 digit ids; 13-digit values that look like epoch milliseconds are skipped.
    "national_id": re.compile(r"(?<![\d.])(?:\d{17}|\d{10}|(?!1[5-8]\d{11})\d{13})(?![\d.])"),
    "bearer_token": re.compile(r"\bBearer\s+[A-Za-z0-9._~+/=-]{20,}", re.IGNORECASE),
    "hf_token": re.compile(r"\bhf_[A-Za-z0-9]{30,}"),
    "github_token": re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})"),
    "google_api_key": re.compile(r"\bAIza[0-9A-Za-z_-]{35}"),
    "private_key": re.compile(r"-----BEGIN (?:[A-Z]+ )*PRIVATE KEY-----"),
    "jwt": re.compile(r"\beyJ[A-Za-z0-9_-]{5,}\.eyJ[A-Za-z0-9_-]{5,}\.[A-Za-z0-9_-]+"),
    # Literal-looking values only (contain a digit or symbol), so `password = 'Password'`
    # label strings and identifiers in source code are not flagged.
    "password_assignment": re.compile(
        r"\b(?:password|passwd|pwd|secret|api[_-]?key)\b[\"']?\s*[:=]\s*[\"']?"
        r"(?![<$*{\s])(?=[^\s\"',;]*[\d!@#$%^&*])[^\s\"',;]{6,}",
        re.IGNORECASE,
    ),
}

_EMAIL_CATEGORY = "email"


def find_sensitive(text: str) -> list[str]:
    """Return sorted unique category names of sensitive data found in text."""
    found = {name for name, pattern in _PATTERNS.items() if pattern.search(text)}
    if _real_email_present(text):
        found.add(_EMAIL_CATEGORY)
    return sorted(found)


PROTECTED_PATH_RE = re.compile(
    r"(?:^|/)(?:"
    r"env(?!\.example\.json$)(?:\.[\w-]+)*\.json"
    r"|key\.properties"
    r"|[^/]*\.jks"
    r"|[^/]*\.keystore"
    r"|google-services\.json"
    r"|GoogleService-Info\.plist"
    r"|\.env(?:\.[^/]+)?"
    r")$"
)


def is_protected_path(path: str) -> bool:
    """True for secret-bearing config files that must never be read, edited or committed."""
    return PROTECTED_PATH_RE.search(path) is not None


ISSUE_REF_RE = re.compile(r"\b(close[sd]?|fix(e[sd])?|resolve[sd]?|refs?)\s+#\d+\b", re.IGNORECASE)

PRIVACY_HEADING = "Privacy check"

REQUIRED_SECTIONS: dict[str, list[str]] = {
    "bug": [
        "App version", "Build flavor", "Device and Android version", "Screen or feature",
        "Steps to reproduce", "Expected behaviour", "Actual behaviour", "Frequency",
        "Impact", PRIVACY_HEADING,
    ],
    "feature": [
        "User", "Problem", "Proposed solution", "Acceptance criteria", "Programme",
        "Offline behaviour", PRIVACY_HEADING,
    ],
    "task": ["What", "Why now", "Risk if not done", PRIVACY_HEADING],
    "release": ["Version", "Release checklist"],
}

TYPE_LABELS: dict[str, str] = {
    "bug": "bug",
    "enhancement": "feature",
    "chore": "task",
    "release": "release",
}

TITLE_PREFIXES: dict[str, str] = {
    "[bug]": "bug",
    "[feature]": "feature",
    "[task]": "task",
    "[release]": "release",
}

BRANCH_RE = re.compile(r"^(feat|fix|chore|docs|refactor|test|hotfix)/\d+-[\w.-]+$")
