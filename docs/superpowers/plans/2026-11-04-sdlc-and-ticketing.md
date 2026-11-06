# LW-SDLC + GitHub Ticketing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the LEAPWELL SDLC process, GitHub Issues ticketing with Claude-led intake, GitHub-side enforcement, and a committed multi-agent toolkit — as one PR, without changing any GitHub setting.

**Architecture:** All enforcement logic lives in stdlib-only Python under `scripts/sdlc/` with one shared patterns module, unit-tested with `unittest`. GitHub Actions, git hooks and Claude Code hooks are thin callers of those scripts. Claude agents/skills are committed under `.claude/` so they load automatically for anyone opening the repo; the `lw-ticket` skill is also zipped for claude.ai org upload.

**Tech Stack:** Python 3.11+ stdlib, GitHub Actions, GitHub issue forms (YAML), `gh` CLI, Bash, Claude Code skills/agents/hooks.

**Spec:** `docs/superpowers/specs/2026-11-04-sdlc-and-ticketing-design.md`

## Global Constraints

- Do NOT run anything that changes GitHub state (labels, projects, protection, issues). Scripts default to dry-run; `--apply` required to mutate.
- Do NOT modify anything under `lib/`, `android/`, `ios/`, `test/` (Dart), or `pubspec.yaml`.
- Python: stdlib only, runs on 3.11+. Tests: `python3 -m unittest discover -s scripts/sdlc/tests -t .` from repo root, all pass.
- Never print a matched secret/PHI value — report the category name only.
- The repo is public: every template/doc that collects user input carries the privacy rule.
- Issue references use GitHub `#N`. Jira is retired — no `LEAP-` references in new files except the migration note.
- Branch names: `feat|fix|chore|docs|refactor|test|hotfix/<issue#>-<slug>`.
- Commit messages end with the session attribution lines supplied by the controller.
- Baseline (2026-11-04, main@82cbd89a): `flutter analyze` 40 errors; `flutter test` 1696 passed / 38 failed. CI ratchets: errors ≤ 40, failures ≤ 38.

## Shared contract — issue sections (used by Tasks 1, 2, 4)

Issue type is detected from labels: `bug` → bug, `enhancement` → feature, `chore` → task, `release` → release. If none, fall back to title prefix `[Bug]`, `[Feature]`, `[Task]`, `[Release]`. Unknown type → only the privacy scan runs.

Body sections are Markdown `### <Heading>` blocks (what GitHub issue forms render). A section is empty if missing, blank, or `_No response_`.

| Type | Required headings (exact text) |
|---|---|
| bug | `App version`, `Build flavor`, `Device and Android version`, `Screen or feature`, `Steps to reproduce`, `Expected behaviour`, `Actual behaviour`, `Frequency`, `Impact`, `Privacy check` |
| feature | `User`, `Problem`, `Proposed solution`, `Acceptance criteria`, `Programme`, `Offline behaviour`, `Privacy check` |
| task | `What`, `Why now`, `Risk if not done`, `Privacy check` |
| release | `Version`, `Release checklist` |

Optional headings — bug: `Logs or screenshots`; feature: `Designs`. `Privacy check` passes only if it contains a ticked box `- [x]` / `- [X]`.

## Review Focus

1. A pasted logcat line with a Bearer token or `hf_` token in an issue — must be flagged by category, value never echoed in the bot comment or Action log.
2. Bangladeshi phone numbers in both `01XXXXXXXXX` and `+880 1XXX-XXXXXX` forms — flagged; app version strings like `1.1.0+15` and dates must NOT be flagged.
3. `git push origin HEAD:main`, `git push -f`, `git commit --no-verify` from Claude — blocked; `git push -u origin feat/12-x` and `flutter build ... --dart-define-from-file=env.production.json` — allowed.
4. An issue edited after the bot labelled it `status:needs-info` and now complete — label removed, no duplicate comments (bot updates one marker comment).
5. A PR body with `closes #12` (lowercase) or `Refs #7` — passes; `#12` alone or `LEAP-12` — fails.

---

### Task 1: Shared SDLC checks (`scripts/sdlc/`)

**Files:**
- Create: `scripts/sdlc/__init__.py`, `scripts/sdlc/patterns.py`, `scripts/sdlc/check_issue.py`, `scripts/sdlc/check_pr.py`, `scripts/sdlc/guard_tool.py`, `scripts/sdlc/commit_msg.py`, `scripts/sdlc/guard_staged.py`
- Test: `scripts/sdlc/tests/__init__.py`, `scripts/sdlc/tests/test_patterns.py`, `test_check_issue.py`, `test_check_pr.py`, `test_guard_tool.py`, `test_commit_msg.py`, `test_guard_staged.py`

**Interfaces (Produces):**
- `patterns.find_sensitive(text: str) -> list[str]` — sorted unique category names among: `bd_phone`, `email`, `national_id`, `bearer_token`, `hf_token`, `github_token`, `google_api_key`, `private_key`, `jwt`, `password_assignment`. Ignores version strings (`1.1.0+15`), dates, and 4–9 digit numbers.
- `patterns.PROTECTED_PATH_RE` / `patterns.is_protected_path(path: str) -> bool` — True for `env*.json` except `env.example.json`, `key.properties`, `*.jks`, `*.keystore`, `google-services.json`, `GoogleService-Info.plist`, `.env`, `.env.*`.
- `patterns.ISSUE_REF_RE` — case-insensitive `\b(close[sd]?|fix(e[sd])?|resolve[sd]?|refs?)\s+#\d+\b`.
- `patterns.REQUIRED_SECTIONS: dict[str, list[str]]` — the contract table above; `patterns.TYPE_LABELS = {"bug":"bug","enhancement":"feature","chore":"task","release":"release"}`.
- `check_issue.evaluate(title: str, body: str, labels: list[str]) -> IssueResult` (dataclass: `issue_type: str|None`, `missing: list[str]`, `privacy_unchecked: bool`, `sensitive: list[str]`, `ok: bool`), and `check_issue.render_comment(result) -> str` starting with the marker `<!-- lw-issue-check -->`. CLI: `python3 -m scripts.sdlc.check_issue --event "$GITHUB_EVENT_PATH"` prints JSON `{"ok":..,"comment":..}` and exits 0 (the workflow decides labels).
- `check_pr.evaluate(body: str, head_ref: str) -> PrResult` (`has_issue_ref`, `branch_ok`, `sensitive`, `ok` = has_issue_ref and not sensitive; branch_ok is a warning only). CLI `--event PATH` exits 1 when not ok, printing reasons.
- `guard_tool.decide(payload: dict) -> str|None` — reason string to deny, else None. Handles `tool_name` `Bash` (`tool_input.command`) and `Read`/`Edit`/`Write` (`tool_input.file_path`). Deny: `git push` with `--force`/`-f`/`--force-with-lease`/`+refspec`; `git push` whose refspec targets `main` or `develop` (incl. `HEAD:main`, `origin main`); bare `git push` when `payload["cwd"]`'s current branch is main/develop (resolved via `git -C cwd rev-parse --abbrev-ref HEAD`, injectable for tests); any `--no-verify`; `git add` of a protected path; display commands (`cat`, `less`, `more`, `head`, `tail`, `bat`, `nl`, `xxd`, `strings`, `base64`) on a protected path; Read/Edit/Write on a protected path. Allow `--dart-define-from-file=env.x.json` and everything else. CLI `main()` reads stdin JSON, on deny prints the reason to stderr and exits 2, else exits 0.
- `commit_msg.check(message: str) -> str|None` — error or None. Pass if first line contains `#\d+` or starts with a Conventional Commit type `(feat|fix|chore|docs|refactor|test|perf|build|ci|style|revert)(\(.+\))?!?: `; also pass merge/revert/fixup!/squash! messages. CLI takes the message file path, exits 1 with the error.
- `guard_staged.check(paths: list[str], read: Callable[[str], str]) -> list[str]` — problems: protected paths staged; sensitive categories found in staged file content (skip binaries and files > 1 MB, and skip `scripts/sdlc/tests/` fixtures). CLI reads `git diff --cached --name-only --diff-filter=ACM`, exits 1 listing `path: category`.

- [ ] **Step 1: Write failing tests** covering every Interfaces bullet and Review Focus items 1, 2, 3 and 5, e.g.:

```python
class TestFindSensitive(unittest.TestCase):
    def test_flags_bd_phone_both_forms(self):
        self.assertEqual(find_sensitive("call 01712345678"), ["bd_phone"])
        self.assertEqual(find_sensitive("call +880 1712-345678"), ["bd_phone"])
    def test_ignores_versions_and_dates(self):
        self.assertEqual(find_sensitive("LEAPWELL 1.1.0+15 on 2026-11-04, build 14"), [])
    def test_bearer_category_only(self):
        self.assertEqual(find_sensitive("Authorization: Bearer " + "a" * 32), ["bearer_token"])

class TestGuardTool(unittest.TestCase):
    def bash(self, cmd, branch="feat/1-x"):
        return decide({"tool_name": "Bash", "tool_input": {"command": cmd}, "cwd": "/r"}, current_branch=lambda cwd: branch)
    def test_blocks(self):
        for c in ["git push origin HEAD:main", "git push -f", "git push origin develop", "git commit -m x --no-verify", "cat env.production.json", "git add android/key.properties"]:
            self.assertIsNotNone(self.bash(c), c)
        self.assertIsNotNone(self.bash("git push", branch="main"))
    def test_allows(self):
        for c in ["git push -u origin feat/12-x", "flutter build apk --dart-define-from-file=env.production.json", "cat env.example.json"]:
            self.assertIsNone(self.bash(c), c)
```

- [ ] **Step 2:** Run `python3 -m unittest discover -s scripts/sdlc/tests -t .` — expect failures (modules missing).
- [ ] **Step 3:** Implement the modules to the Interfaces above. `check_issue.render_comment` lists missing headings and sensitive categories, tells the reporter to edit the issue, never includes matched values.
- [ ] **Step 4:** Run the suite — all pass.
- [ ] **Step 5:** Commit `feat(sdlc): shared issue/PR/commit/secret checks`.

### Task 2: GitHub configuration (`.github/`)

**Files:**
- Create: `.github/ISSUE_TEMPLATE/bug.yml`, `feature.yml`, `task.yml`, `release.yml`, `config.yml`; `.github/pull_request_template.md`; `.github/CODEOWNERS`; `.github/labels.yml`; `.github/workflows/issue-check.yml`, `pr-check.yml`, `ci.yml`
- Modify: `.github/workflows/android-apk.yml` (remove the non-blocking analyze/test steps now owned by `ci.yml`; also trigger on PRs to `develop`)
- Test: `scripts/sdlc/tests/test_github_config.py`

**Interfaces:** Consumes Task 1 CLIs and `REQUIRED_SECTIONS`.

- Issue forms: each `label:` of a body field equals a heading from the contract table (so the rendered `### <label>` matches); required headings have `validations: required: true`; `Privacy check` is a `checkboxes` field with one required option "This issue contains no patient/member data, names, phone numbers, IDs, credentials, tokens or unscrubbed logs (this repo is public)". Forms set `labels:` (`bug`/`enhancement`/`chore`/`release`) and `title:` prefix (`[Bug] `, `[Feature] `, `[Task] `, `[Release] `). Bug `Build flavor` is a dropdown (`prod (LEAPWELL)`, `training (LW Training)`, `dev`); `Frequency` dropdown (Always, Often, Sometimes, Once); `Impact` dropdown (SKs cannot work, Workaround exists, Cosmetic). Feature `Programme` dropdown (ANC, PNC, NCD, IMCI/iCCM, TB, EPI, Nutrition, Family planning, Eye care, Cross-cutting).
- `config.yml`: `blank_issues_enabled: false`; contact link "Report a security vulnerability (private)" → `https://github.com/Medtronic-LABS/uhis_lf_mobile/security/advisories/new`; contact link to `docs/process/TICKETS.md` on GitHub.
- PR template: `Closes #` line, Summary, Size (S/M/L), Test evidence, Screenshots (no real patient data), Risk & rollback, checklist mirroring the Definition of Done in the spec.
- CODEOWNERS: `* @Medtronic-LABS/leapfrogging`; `@amreshyadavgit @adityab24840` added on `/.github/`, `/lib/core/auth/`, `/lib/core/db/`, `/lib/core/api/endpoints.dart`, `/android/`, `/pubspec.yaml`, `/scripts/release.sh`, `/.claude/`, `/scripts/sdlc/`.
- `labels.yml`: list of `{name, color, description}` — keep existing 12; add `release`, `area:{auth,sync,db,visit,cdss,scribe,coaching,teleconsult,household,push,release,ci,i18n}`, `prio:P0`..`P3`, `env:{prod,training,dev}`, `status:{needs-info,blocked,needs-design}`.
- `issue-check.yml`: on `issues: [opened, edited, labeled]`; `permissions: issues: write, contents: read`; checkout; run `check_issue`; with `gh`, upsert the single marker comment (edit if exists, delete it when ok) and add/remove `status:needs-info`. Body never echoed to logs.
- `pr-check.yml`: on `pull_request: [opened, edited, synchronize, reopened]`; runs `check_pr`; job name `pr-check`.
- `ci.yml`: on PRs to `develop` and `main` + push to those; jobs `sdlc-scripts` (python unittest), `secret-scan` (gitleaks-action, full history checkout), `flutter` (flutter 3.44.8, `flutter pub get`, `flutter analyze` counted against `ANALYZE_ERROR_BUDGET: 40`, `flutter test` counted against `TEST_FAILURE_BUDGET: 38` — fail when over budget, print the counts; budgets documented as ratchet-down-only).

- [ ] **Step 1: Write failing test** `test_github_config.py`: parse the issue form YAML with a minimal reader (stdlib — use `json`-compatible subset or a tiny line-based extractor of `label:` values under `body:`; do not add PyYAML) and assert every required heading from `REQUIRED_SECTIONS[type]` appears as a field label in the matching form, that each form has the privacy checkbox, and that `config.yml` disables blank issues.
- [ ] **Step 2:** Run — fails.
- [ ] **Step 3:** Create the files above.
- [ ] **Step 4:** Run unittest suite — passes. If `actionlint` is installed, run it on `.github/workflows/` and fix findings; otherwise note it in the report.
- [ ] **Step 5:** Commit `ci(github): issue forms, PR template, CODEOWNERS, labels, checks`.

### Task 3: Admin scripts (`scripts/github/`) — dry-run by default

**Files:** Create `scripts/github/sync_labels.sh`, `setup_project.sh`, `protect_branches.sh`, `package_skill.sh`; Test: `scripts/sdlc/tests/test_admin_scripts.py`

- Every mutating script: `set -euo pipefail`; default prints the exact `gh` commands it would run; `--apply` runs them; `--help`. Owner/repo/project number are variables at the top (`OWNER=Medtronic-LABS`, `REPO=uhis_lf_mobile`, `PROJECT=4`).
- `sync_labels.sh`: reads `.github/labels.yml` (via `python3 -c` stdlib parse) → `gh label create NAME --color C --description D --force`.
- `setup_project.sh`: prints/applies Priority options P0–P3, Status options Triage, Backlog, Ready, In progress, In review, QA, Done (via `gh api graphql` `updateProjectV2Field` — note in script output that Status option edits replace the option list, so existing item statuses must be checked first), and an Iteration field "Sprint" (2 weeks). Lists built-in workflows to enable manually (UI-only).
- `protect_branches.sh`: `main` (2 approvals, CODEOWNERS review, dismiss stale, required checks `pr-check`, `sdlc-scripts`, `secret-scan`, `flutter`, `build-apk`, no force push/deletion, enforce admins false) and `develop` (1 approval, same checks).
- `package_skill.sh`: zips `.claude/skills/lw-ticket/` into `dist/skills/lw-ticket.zip` with the folder named `lw-ticket` at the zip root (non-mutating, no `--apply` needed).
- [ ] Steps: failing test (scripts exist, executable, `--help` exits 0, dry-run of each prints `gh` and does not call it — run with `PATH` containing a fake `gh` that exits 99), implement, pass, commit `chore(github): dry-run admin scripts for labels, project, protection`.

### Task 4: Claude toolkit + git hooks

**Files:**
- Create: `.claude/settings.json`; `.claude/agents/lw-architect.md`, `lw-implementer.md`, `lw-reviewer.md`, `lw-qa.md`, `lw-security.md`, `lw-release.md`; `.claude/skills/lw-ticket/SKILL.md`, `.claude/skills/lw-ticket/references/{bug,feature,task,release}.md`, `.claude/skills/lw-ticket/references/privacy.md`; `.claude/skills/lw-start/SKILL.md`, `lw-feature/SKILL.md`, `lw-fix/SKILL.md`, `lw-pr/SKILL.md`, `lw-release/SKILL.md`; `.githooks/commit-msg`, `.githooks/pre-commit`; `scripts/setup_dev.sh`
- Test: `scripts/sdlc/tests/test_claude_toolkit.py`

**Interfaces:** Consumes Task 1 CLIs and the section contract; Task 2 label names.

- `.claude/settings.json`: `hooks.PreToolUse` matcher `Bash|Read|Edit|Write` → `python3 "$CLAUDE_PROJECT_DIR"/scripts/sdlc/guard_tool.py` (timeout 10). No `enabledPlugins` / personal settings.
- Agents (frontmatter `name`, `description`, `tools`, `model`): architect (Read, Grep, Glob, Bash; opus; proposes only), implementer (all edit tools; sonnet; TDD, one task, never pushes/merges/spawns agents), reviewer (Read, Grep, Glob, Bash; opus; two verdicts Spec ✅/❌ and Quality Approved/Changes, checks Engineering Design Standards from CLAUDE.md), qa (Read, Grep, Glob, Bash, Write, Edit; sonnet; test files only), security (Read, Grep, Glob, Bash; opus; PHI, secrets, auth, crypto, logging), release (Read, Grep, Glob, Bash; sonnet; version/AAB/signer/notes checklist, never uploads or tags without the human). Each body states hard limits: never merge, never set priority, never touch prod keys, never print secrets.
- `lw-ticket` SKILL.md: frontmatter `name: lw-ticket`, `description` that triggers on "file/create/raise/log a bug/ticket/issue/feature request/task". Body works in both surfaces: Claude Code uses `gh` (+ `AskUserQuestion` where available); chat asks conversationally and uses the GitHub connector's issue tool (`issue_write` method `create` on the GitHub MCP server) — if no GitHub tool is available, output the finished issue as Markdown plus a prefilled `https://github.com/Medtronic-LABS/uhis_lf_mobile/issues/new?template=<type>.yml` link. Flow: type → duplicate search (`gh issue list --search` / connector search) → one question at a time from `references/<type>.md` → privacy scrub per `references/privacy.md` (security → private advisory link, stop) → propose labels (`area:*`, `prio:*` suggestion only, `env:*`) → full preview → create only after explicit "yes" → `gh project item-add 4 --owner Medtronic-LABS --url <issue>` (Code only) → return link. Body headings exactly the contract table. In Claude Code, may read app version/device via `adb` when a device is connected and the user agrees.
- `lw-start` (arg issue #): read issue, check Definition of Ready, size S/M/L, propose branch `type/N-slug`, create it, comment plan on issue. `lw-feature`: L flow (brainstorm → spec → plan → subagent loop → final review → `lw-pr`). `lw-fix`: S/M flow (systematic debugging → failing test → fix → reviewer agent → `lw-pr`). `lw-pr`: run `python3 -m unittest …`, `flutter analyze`, related tests; fill PR template with `Closes #N`; `gh pr create --draft` to `develop`. `lw-release`: checklist (bump pubspec via PR, notes from milestone, tag only on human say-so). All `disable-model-invocation: true` except `lw-ticket`.
- `.githooks/commit-msg` → `python3 scripts/sdlc/commit_msg.py "$1"`; `.githooks/pre-commit` → `python3 scripts/sdlc/guard_staged.py`. `scripts/setup_dev.sh`: `git config core.hooksPath .githooks`, chmod hooks, print next steps.
- [ ] Steps: failing test (settings.json valid JSON with the hook; every agent/skill file starts with `---`, has `name` equal to its folder/file stem and a `description`; lw-ticket references contain every contract heading for their type; hooks executable), implement, pass; manually pipe a JSON payload into `guard_tool.py` to confirm exit 2 / 0; commit `feat(claude): shared agents, skills and guard hooks`.

### Task 5: Process docs, CLAUDE.md, repo hygiene

**Files:**
- Create: `docs/process/SDLC.md`, `docs/process/TICKETS.md`, `docs/process/CLAUDE_ADMIN_SETUP.md`, `docs/process/JIRA_RETIREMENT.md`
- Modify: `CLAUDE.md` (add "Process & ticketing" section near top pointing to the docs, skills and agents; state Jira retired; keep everything else), `.gitignore` (add `.claude/worktrees/`, `env.*.json` with `!env.example.json`, `dist/`), `README.md` if it describes contribution flow (link SDLC.md)
- Remove from index (not disk): the five gitlinks under `.claude/worktrees/` (`git rm --cached`).
- Test: `scripts/sdlc/tests/test_docs.py`

- `SDLC.md` (≤ ~250 lines): roles & human-only gates; S/M/L table with required path; issue lifecycle (Triage → Backlog → Ready → In progress → In review → QA → Done) with Definition of Ready / Done; branching + naming; PR rules (`Closes #N`, checks, approvals); CI gates + ratchet budgets and how to lower them; release flow (pubspec bump PR → `v*` tag → `release.yml` → Play internal → closed → staged prod; release notes EN/BN ≤ 500 chars); hotfix; multi-agent workflow (which agent/skill when, the task loop, ledger, rulings, what agents may never do); one-time dev setup (`scripts/setup_dev.sh`, gh auth).
- `TICKETS.md` (PM/QA, ≤ 1 page): how to file via Claude Desktop/claude.ai (lw-ticket) or Claude Code (`/lw-ticket`), what Claude will ask, privacy rule, screenshots attached afterwards via web, fallback web forms, triage cadence, label meanings.
- `CLAUDE_ADMIN_SETUP.md`: owner uploads `dist/skills/lw-ticket.zip` (built by `scripts/github/package_skill.sh`) in claude.ai org skills (Team/Enterprise, Owner role); add GitHub custom connector `https://api.githubcopilot.com/mcp/` (each user OAuths with own account; note to verify OAuth works in your org, fallback is the prefilled link mode); GitHub org admin steps — run `sync_labels.sh`, `setup_project.sh`, `protect_branches.sh` (dry-run first), enable project built-in workflows, enable private vulnerability reporting.
- `JIRA_RETIREMENT.md`: decision + date, steps to move open LEAP tickets (create via lw-ticket, link old key in body once, close Jira with link), freeze date placeholder for owner.
- [ ] Steps: failing test (docs exist; `SDLC.md` mentions every skill and agent name; no `LEAP-\d` outside JIRA_RETIREMENT.md in new docs; `.gitignore` contains the new rules; `git ls-files .claude/worktrees` empty), implement, pass, commit `docs(process): SDLC, ticketing guides, Jira retirement; repo hygiene`.
