"""Tests for scripts.sdlc.guard_tool (Claude Code PreToolUse hook)."""
import io
import json
import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

from scripts.sdlc import guard_tool
from scripts.sdlc.guard_tool import decide

REPO_ROOT = Path(__file__).resolve().parents[3]


def bash(cmd, branch="feat/1-x"):
    payload = {"tool_name": "Bash", "tool_input": {"command": cmd}, "cwd": "/r"}
    return decide(payload, current_branch=lambda cwd: branch)


class TestBashDeny(unittest.TestCase):
    def test_blocks(self):
        for cmd in [
            "git push origin HEAD:main", "git push -f", "git push --force origin feat/1-x",
            "git push --force-with-lease", "git push origin +feat/1-x", "git push origin develop",
            "git push origin main", "git push origin feat/1-x:main", "git push origin :main",
            "git push origin refs/heads/main", "git push --all", "git push -uf origin feat/1-x",
            "git commit -m x --no-verify", "git push --no-verify", "git commit -nm x",
            "cat env.production.json", "head -n 3 env.development.json", "base64 android/key.properties",
            "git add android/key.properties", "git add -A env.production.json",
            "git -C /r push origin main", "git -c core.x=1 push -f",
            "sudo git push -f", "env FOO=1 git push -f", "command git push origin main",
            "nohup git push origin develop", "exec git push -f", "time git push -f",
            "sudo -n git push -f", "env -i git push origin main",
            "git -c core.hooksPath=/dev/null commit -m x",
            "git -c core.hooksPath=/dev/null push origin feat/1-x",
            "git -c core.hookspath=/tmp/h commit -m x",
        ]:
            self.assertIsNotNone(bash(cmd), cmd)

    def test_bare_push_on_protected_branch(self):
        for branch in ("main", "develop"):
            self.assertIsNotNone(bash("git push", branch=branch))
            self.assertIsNotNone(bash("git push origin", branch=branch))
            self.assertIsNotNone(bash("git push origin HEAD", branch=branch))
            self.assertIsNotNone(bash("git push -u origin", branch=branch))

    def test_dash_c_dir_resolves_branch_from_that_dir(self):
        def resolver(cwd):
            return "main" if cwd == "/r/sub" else "feat/1-x"

        def run(cmd):
            payload = {"tool_name": "Bash", "tool_input": {"command": cmd}, "cwd": "/r"}
            return decide(payload, current_branch=resolver)

        self.assertIsNotNone(run("git -C sub push"))
        self.assertIsNotNone(run("git -C /r/sub push origin HEAD"))
        self.assertIsNone(run("git -C other push"))
        self.assertIsNone(run("git push"))

    def test_unknown_branch_bare_push_notes_on_stderr(self):
        err = io.StringIO()
        with mock.patch("sys.stderr", err):
            self.assertIsNone(bash("git push", branch=None))
        self.assertEqual(err.getvalue().strip(),
                         "lw-guard: could not determine current branch; bare push allowed")

    def test_known_branch_push_is_silent(self):
        err = io.StringIO()
        with mock.patch("sys.stderr", err):
            self.assertIsNone(bash("git push", branch="feat/1-x"))
        self.assertEqual(err.getvalue(), "")

    def test_unknown_branch_bare_push_allowed(self):
        self.assertIsNone(bash("git push", branch=None))

    def test_chained_commands(self):
        for cmd in [
            "git add -A && git push origin HEAD:main",
            "echo hi; git push -f",
            "git status | cat env.production.json",
            "false || git commit --no-verify -m x",
            "cd /r && git push origin develop && echo done",
            'bash -c "git push -f"',
            "FOO=1 git push -f",
        ]:
            self.assertIsNotNone(bash(cmd), cmd)

    def test_allows(self):
        for cmd in [
            "git push -u origin feat/12-x",
            "git push origin feat/12-x",
            "flutter build apk --dart-define-from-file=env.production.json",
            "flutter run --dart-define-from-file=env.development.json",
            "cat env.example.json",
            "git add lib/main.dart",
            'git commit -m "docs: mention --no-verify is blocked"',
            'git commit -m "feat: x; and git push -f"',
            "git status && git log --oneline",
            "ls",
            "git push origin feat/1-main-thing",
            "git push --no-force-with-lease origin feat/1-x",
            "git commit -m -n",
            'git commit -m "-n"',
            "git commit -am -n",
            "git -c user.name=x commit -m y",
            "sudo ls", "env FOO=1 flutter test", "time git status",
        ]:
            self.assertIsNone(bash(cmd), cmd)

    def test_reason_is_a_string(self):
        self.assertIsInstance(bash("git push -f"), str)


class TestFileTools(unittest.TestCase):
    def file_tool(self, tool, path):
        return decide({"tool_name": tool, "tool_input": {"file_path": path}})

    def test_protected_blocked(self):
        for tool in ("Read", "Edit", "Write"):
            for path in ("/r/env.production.json", "/r/android/key.properties", "/r/.env"):
                self.assertIsNotNone(self.file_tool(tool, path), (tool, path))

    def test_other_allowed(self):
        for tool in ("Read", "Edit", "Write"):
            for path in ("/r/env.example.json", "/r/lib/main.dart"):
                self.assertIsNone(self.file_tool(tool, path), (tool, path))

    def test_other_tools_allowed(self):
        self.assertIsNone(decide({"tool_name": "Glob", "tool_input": {"pattern": "env*.json"}}))


class TestGrep(unittest.TestCase):
    def grep(self, **tool_input):
        return decide({"tool_name": "Grep", "tool_input": {"pattern": "x", **tool_input}})

    def test_protected_path_blocked(self):
        for path in ("/r/env.production.json", "android/key.properties", "/r/.env", "/r/app/upload.jks"):
            self.assertIsNotNone(self.grep(path=path), path)

    def test_glob_targeting_secret_files_blocked(self):
        for glob in ("env*.json", "env.production.json", "**/env.*.json", "*.json", "*.properties", "*.jks", ".env*"):
            self.assertIsNotNone(self.grep(glob=glob), glob)

    def test_directories_and_safe_globs_allowed(self):
        self.assertIsNone(self.grep())
        self.assertIsNone(self.grep(path="lib"))
        self.assertIsNone(self.grep(path="/r/lib/main.dart"))
        self.assertIsNone(self.grep(path="/r/env.example.json"))
        for glob in ("*.dart", "**/*.yml", "env.example.json", "lib/**/*.dart"):
            self.assertIsNone(self.grep(path="lib", glob=glob), glob)

    def test_non_string_inputs_allowed(self):
        self.assertIsNone(self.grep(path=None, glob=["env*.json"]))


class TestMalformed(unittest.TestCase):
    def test_decide_never_raises(self):
        for payload in (
            {}, {"tool_name": "Bash"}, {"tool_name": "Bash", "tool_input": None},
            {"tool_name": "Bash", "tool_input": {"command": None}},
            {"tool_name": "Bash", "tool_input": {"command": 5}},
            {"tool_name": "Read", "tool_input": {}},
            {"tool_name": "Bash", "tool_input": {"command": 'echo "unterminated'}},
            [], "x", None,
        ):
            self.assertIsNone(decide(payload, current_branch=lambda cwd: None), payload)

    def run_main(self, stdin_text):
        err = io.StringIO()
        with mock.patch("sys.stdin", io.StringIO(stdin_text)), mock.patch("sys.stderr", err):
            code = guard_tool.main()
        return code, err.getvalue()

    def test_main_garbage_allows(self):
        for text in ("", "not json", "[1,2]", "null"):
            self.assertEqual(self.run_main(text), (0, ""), text)

    def test_main_deny(self):
        payload = {"tool_name": "Bash", "tool_input": {"command": "git push -f"}, "cwd": "/r"}
        code, err = self.run_main(json.dumps(payload))
        self.assertEqual(code, 2)
        self.assertTrue(err.strip())

    def test_main_allow_is_silent(self):
        payload = {"tool_name": "Bash", "tool_input": {"command": "ls"}}
        self.assertEqual(self.run_main(json.dumps(payload)), (0, ""))


class TestEntrypoints(unittest.TestCase):
    def run_cmd(self, cmd, stdin):
        return subprocess.run(cmd, cwd=REPO_ROOT, input=stdin, capture_output=True, text=True)

    def test_both_invocation_forms(self):
        deny = json.dumps({"tool_name": "Bash", "tool_input": {"command": "git push -f"}})
        allow = json.dumps({"tool_name": "Read", "tool_input": {"file_path": "lib/main.dart"}})
        for cmd in (
            [sys.executable, "scripts/sdlc/guard_tool.py"],
            [sys.executable, "-m", "scripts.sdlc.guard_tool"],
        ):
            denied = self.run_cmd(cmd, deny)
            self.assertEqual(denied.returncode, 2, denied.stderr)
            self.assertTrue(denied.stderr.strip())
            allowed = self.run_cmd(cmd, allow)
            self.assertEqual((allowed.returncode, allowed.stderr, allowed.stdout), (0, "", ""))


if __name__ == "__main__":
    unittest.main()
