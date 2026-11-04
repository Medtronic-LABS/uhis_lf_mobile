"""Claude Code PreToolUse hook: deny risky git operations and secret-file access.

Reads the hook payload JSON on stdin. On deny, prints the reason to stderr and
exits 2; otherwise exits 0 silently. Malformed input is always allowed.
"""
import json
import os
import re
import shlex
import subprocess
import sys
from pathlib import Path
from typing import Any, Callable, Optional

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from scripts.sdlc.patterns import is_protected_path  # noqa: E402

BranchResolver = Callable[[str], Optional[str]]

PROTECTED_BRANCHES = {"main", "develop"}
FILE_TOOLS = {"Read", "Edit", "Write"}
DISPLAY_COMMANDS = {"cat", "less", "more", "head", "tail", "bat", "nl", "xxd", "strings", "base64"}
SHELLS = {"bash", "sh", "zsh"}
OPERATORS = {"&&", "||", ";", "|", "&"}
GIT_OPTS_WITH_VALUE = {"-C", "-c", "--git-dir", "--work-tree", "--namespace"}
PUSH_FORCE_LONG = ("--force", "--force-with-lease", "--force-if-includes")
PUSH_ALL_FLAGS = {"--all", "--mirror"}
_ENV_ASSIGN_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*=")
_SHORT_CLUSTER_RE = re.compile(r"^-[A-Za-z]+$")


def git_current_branch(cwd: str) -> Optional[str]:
    try:
        done = subprocess.run(
            ["git", "-C", cwd, "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True, text=True, timeout=5,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return done.stdout.strip() or None if done.returncode == 0 else None


def tokenize(command: str) -> list[str]:
    lexer = shlex.shlex(command, posix=True, punctuation_chars=True)
    lexer.whitespace_split = True
    try:
        return list(lexer)
    except ValueError:
        return command.split()


def split_segments(tokens: list[str]) -> list[list[str]]:
    segments: list[list[str]] = [[]]
    for token in tokens:
        if token in OPERATORS:
            segments.append([])
        else:
            segments[-1].append(token)
    return [segment for segment in segments if segment]


def strip_prefixes(segment: list[str]) -> list[str]:
    index = 0
    while index < len(segment) and _ENV_ASSIGN_RE.match(segment[index]):
        index += 1
    return segment[index:]


def git_subcommand(args: list[str]) -> tuple[Optional[str], list[str]]:
    """Return (subcommand, remaining args) for the args after `git`."""
    index = 0
    while index < len(args) and args[index].startswith("-"):
        index += 2 if args[index] in GIT_OPTS_WITH_VALUE else 1
    if index >= len(args):
        return None, []
    return args[index], args[index + 1:]


def _has_short_flag(args: list[str], flag: str) -> bool:
    return any(_SHORT_CLUSTER_RE.match(a) and flag in a[1:] for a in args)


def refspec_target(refspec: str) -> str:
    target = refspec.rpartition(":")[2] if ":" in refspec else refspec
    return target.lstrip("+").removeprefix("refs/heads/")


def check_push(args: list[str], cwd: str, current_branch: BranchResolver) -> Optional[str]:
    if any(a.startswith(PUSH_FORCE_LONG) for a in args) or _has_short_flag(args, "f"):
        return "Force-push is blocked. Push your feature branch normally."
    positionals = [a for a in args if not a.startswith("-")]
    refspecs = positionals[1:]
    if any(r.startswith("+") for r in refspecs):
        return "Force-push (+refspec) is blocked. Push your feature branch normally."
    if PUSH_ALL_FLAGS & set(args):
        return "Pushing all branches would include main/develop. Push your feature branch by name."
    if refspecs:
        branch = current_branch(cwd)
        targets = {branch if r == "HEAD" else refspec_target(r) for r in refspecs}
    else:
        targets = {current_branch(cwd)}
    if targets & PROTECTED_BRANCHES:
        return "Direct pushes to main/develop are blocked. Push a feature branch and open a PR."
    return None


def check_git(args: list[str], cwd: str, current_branch: BranchResolver) -> Optional[str]:
    subcommand, rest = git_subcommand(args)
    if subcommand == "commit" and _has_short_flag(rest, "n"):
        return "Skipping hooks (-n / --no-verify) is blocked."
    if subcommand == "push":
        return check_push(rest, cwd, current_branch)
    if subcommand == "add" and any(is_protected_path(a) for a in rest if not a.startswith("-")):
        return "Staging secret/config files (env*.json, key.properties, keystores, .env) is blocked."
    return None


def check_segment(segment: list[str], cwd: str, current_branch: BranchResolver) -> Optional[str]:
    segment = strip_prefixes(segment)
    if not segment:
        return None
    if "--no-verify" in segment:
        return "Skipping hooks (--no-verify) is blocked."
    program = os.path.basename(segment[0])
    if program in SHELLS and "-c" in segment[1:-1]:
        return check_command(segment[segment.index("-c") + 1], cwd, current_branch)
    if program == "git":
        return check_git(segment[1:], cwd, current_branch)
    if program in DISPLAY_COMMANDS and any(is_protected_path(a) for a in segment[1:]):
        return "Displaying secret/config files (env*.json, key.properties, keystores, .env) is blocked."
    return None


def check_command(command: str, cwd: str, current_branch: BranchResolver) -> Optional[str]:
    for segment in split_segments(tokenize(command)):
        reason = check_segment(segment, cwd, current_branch)
        if reason:
            return reason
    return None


def decide(payload: Any, *, current_branch: BranchResolver = git_current_branch) -> Optional[str]:
    """Return a deny reason for the hook payload, or None to allow."""
    if not isinstance(payload, dict):
        return None
    tool_input = payload.get("tool_input")
    if not isinstance(tool_input, dict):
        return None
    tool = payload.get("tool_name")
    if tool in FILE_TOOLS:
        path = tool_input.get("file_path")
        if isinstance(path, str) and is_protected_path(path):
            return "Access to secret/config files (env*.json, key.properties, keystores, .env) is blocked."
        return None
    command = tool_input.get("command")
    if tool == "Bash" and isinstance(command, str):
        cwd = payload.get("cwd") if isinstance(payload.get("cwd"), str) else os.getcwd()
        return check_command(command, cwd, current_branch)
    return None


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        reason = decide(payload)
    except (json.JSONDecodeError, KeyError, TypeError, AttributeError, ValueError):
        return 0
    if reason:
        print(reason, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
