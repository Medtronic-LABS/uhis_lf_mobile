# LEAPWELL SDLC

How work moves from an idea to the Play Store for `uhis_lf_mobile`. Short on purpose: ceremony
scales with the size of the change. Design record:
[`docs/superpowers/specs/2026-11-04-sdlc-and-ticketing-design.md`](../superpowers/specs/2026-11-04-sdlc-and-ticketing-design.md).

- **Tickets live in [leapwell](https://github.com/Medtronic-LABS/leapwell).** Everyone files bugs, features, tasks and releases there
  (see `docs/process/SDLC.md` and `TICKETS.md` in leapwell). A developer routes each item into
  sub-issues here with `/lw-route` from the leapwell workspace; work, PRs and Project "LeapWell"
  (#4) tracking happen on those sub-issues. Jira is retired ([JIRA_RETIREMENT.md](JIRA_RETIREMENT.md)).
- **The repo is public.** No patient/member data, names, phone numbers, IDs, credentials, tokens or
  unscrubbed logs in issues, PRs, commits, tests or screenshots. Security problems go to a
  [private advisory](https://github.com/Medtronic-LABS/uhis_lf_mobile/security/advisories/new).
- **Code standards:** `CLAUDE.md` and the root "Engineering Design Standards".

```
 idea / bug
    │  /lw-ticket in leapwell, then /lw-route          Project Status
    ▼
 Sub-issue ──► Triage (humans: priority, area, size, owner)    Triage
    │                                                      Backlog → Ready
    ▼  /lw-start <N>   (Definition of Ready, size, branch)
 type/<N>-<slug> from develop                              In progress
    │  S/M: /lw-fix      L: /lw-feature (spec → plan → task loop)
    ▼  /lw-pr          (checks, Closes #N, draft PR)
 PR → develop ── CI + reviews ── human merges              In review
    │  training build verified by QA                       QA
    ▼
 pubspec bump PR ─► develop → main PR ─► v* tag ─► release.yml ─► Play
    internal → closed → staged prod                        Done
```

## 1. Roles and human-only gates

| Role | Does |
|---|---|
| Reporter (anyone: dev, QA, PM) | Files tickets through Claude (`lw-ticket`) or the issue forms |
| Triager (lead + PM, twice a week) | Sets priority, area, size, owner; moves Triage → Backlog/Ready |
| Developer | Picks up Ready issues, works with the agents, owns the PR |
| Reviewer (human) | Reviews and approves PRs; CODEOWNERS for sensitive paths |
| QA | Verifies on the training build, moves the card to Done or back |
| Release owner | Bumps version, tags, uploads to Play |

**Only humans may:** approve a spec, set priority, merge a PR, tag or release, upload to Play,
handle prod keys / secrets / `key.properties` / `env*.json`, and grant a security exception.
Claude proposes; a person decides.

## 2. Sizes

`/lw-start` proposes a size with a one-line reason; the developer can override it. The same
definitions are in the PR template.

| Size | What it is | Required path |
|---|---|---|
| S | About 50 changed lines or fewer and no new behaviour: bug fix, copy, small refactor | issue → branch → failing test + fix (`/lw-fix`) → `lw-reviewer` → PR → 1 human review |
| M | New behaviour inside one existing feature | as S, plus a short design note (approach, files, offline behaviour, risks) shown before coding and copied into the PR → 1 human review |
| L | New module, DB schema/migration, sync, auth, AI or push change — judged by nature, not line count | spec + plan under `docs/superpowers/`, human approves the spec, subagent task loop (`/lw-feature`), final whole-branch review → 2 human reviews |

Anything touching auth, db, sync, scribe, push, logging or build config also gets `lw-security`.

## 3. Issue lifecycle

Project #4 Status: Triage → Backlog → Ready → In progress → In review → QA → Done

| Status | Who moves it | Meaning |
|---|---|---|
| Triage | automatic (issue added) | New; not yet looked at |
| Backlog | triager | Accepted, prioritised, not scheduled |
| Ready | triager / lead | Meets the Definition of Ready; can be picked up |
| In progress | developer | Branch exists, work started |
| In review | developer | PR open and marked ready for review |
| QA | developer after merge | On `develop`; waiting for QA on the training build |
| Done | QA (or automatic on close) | Verified; issue closed |

Ticket completeness and privacy are checked in leapwell when the ticket is filed.

### Definition of Ready

- The leapwell ticket is complete: a bug has steps to
  reproduce, expected and actual behaviour; a feature has acceptance criteria and offline behaviour.
- Triaged: a `prio:*` label (set by a human) and one `area:*` label.
- Not `status:blocked` or `status:needs-design`; open questions answered.
- Size agreed; L-size has an approved spec before implementation starts.

### Definition of Done

- PR merged to `develop` with `Closes #N`; all required checks green.
- New public behaviour has a test; bugs have a regression test.
- No hardcoded user-facing strings (`app_strings.dart`) or config (`AppConfig`); no swallowed errors.
- No secrets, env files or patient data committed.
- Offline behaviour verified where relevant.
- Docs updated where behaviour changed.
- QA verified on the training build (bugs: on the reported device/Android version when possible).

## 4. Branching

- Long-lived: `main` (released) and `develop` (integration). Nobody pushes to either directly; the
  guard hook blocks it in Claude Code and branch protection blocks it on GitHub.
- Work branches from `develop`: `<type>/<N>-<slug>`, type one of
  `feat | fix | chore | docs | refactor | test | hotfix`. Example: `fix/123-sync-stuck-90`.
- Commits: Conventional Commit subject with the issue, e.g. `fix(sync): retry upload on 503 (#123)`.
  The `commit-msg` hook requires a `#N` or a Conventional Commit type.
  Rejected: `PNC service added`. Fixed: `feat(pnc): add PNC service #123`.
- Keep a branch to one issue. Rebase or merge `develop` in as needed; never force-push shared branches.

## 5. Pull requests

- Open with `/lw-pr` (draft PR to `develop`; `hotfix/*` to `main`). It runs the checks and fills
  `.github/pull_request_template.md`.
- The body's first line is `Closes #N` (local sub-issue; or `Fixes` / `Resolves`), or
  `Refs Medtronic-LABS/leapwell#N` / `Refs #N` when it does not fully resolve the issue. The `pr-check` workflow fails without it; a bare `#N` is not enough.
- Fill Size, Test evidence, Screenshots (test data only), Risk & rollback, and tick the Definition
  of Done honestly.
- Approvals: `develop` 1, `main` 2, plus CODEOWNERS for `.github/`, `.claude/`, auth, db,
  `endpoints.dart`, `android/`, `pubspec.yaml`, `scripts/release.sh`, `scripts/sdlc/`.
  L-size PRs need 2 human reviews even into `develop`.
- Required checks: `pr-check`, `sdlc-scripts`, `secret-scan`, `flutter`, `build-apk`.
- Stale approvals are dismissed on new pushes; conversations must be resolved before merge.
- A human merges.

## 6. CI gates

| Workflow | Job | Gate |
|---|---|---|
| `ci.yml` | `sdlc-scripts` | `python3 -m unittest discover -s scripts/sdlc/tests -t .` must pass |
| `ci.yml` | `secret-scan` | gitleaks on the PR's commit range must be clean |
| `ci.yml` | `flutter` | analyzer errors and failing tests within the budgets below |
| `pr-check.yml` | `pr-check` | issue link present; branch name and sensitive-data checks |
| `android-apk.yml` | `build-apk` | release APK builds |

### Ratchet budgets

The codebase started with known analyzer errors and failing tests, so the `flutter` job fails only
when a PR makes things **worse**: analyzer errors may not exceed `ANALYZE_ERROR_BUDGET` and failing
tests may not exceed `TEST_FAILURE_BUDGET`. Both live only in the `flutter` job's `env:` in
`.github/workflows/ci.yml` — that file is the single source of the current numbers.

**Ratchet down, never up.** When your PR fixes analyzer errors or failing tests, lower the budget
in `ci.yml` to the new count **in the same PR**. Raising a budget needs an explicit human decision
recorded in the PR. Goal: both at 0.

## 7. Release

Full checklist and Play Console notes: [`RELEASE_PLAN.md`](../../RELEASE_PLAN.md). Walk it with
`/lw-release` (the `lw-release` agent checks readiness).

1. File a `[Release] <version>` ticket in leapwell (`/lw-ticket` → Release) and route it here.
2. Version bump: `pubspec.yaml` is the only version source. Bump via its own
   `chore/<N>-bump-<version>` PR to `develop`; the build number always increases.
3. `develop` → `main` PR once QA has verified the training build. The PR body must contain
   `Refs #<release issue>` (the Release issue from the release form).
4. Release notes in English and Bangla, each 500 characters or fewer, user-facing language,
   no internal IDs or patient data.
5. Tag `v<version>` on `main` (human, via `scripts/release.sh production "" --tag` then
   `git push origin v<version>`). `release.yml` builds the signed bundle, verifies the signer and
   attaches it to a GitHub Release.
6. Play Console (human): internal → closed testing → staged production rollout.
7. Tick the release issue, close the milestone.

## 8. Hotfix

For a prod P0/P1 the team agrees cannot wait for the next release:

1. Issue as usual; branch `hotfix/<N>-<slug>` from `origin/main`.
2. `/lw-fix` (failing test first), `/lw-pr` opens the PR to `main` (2 approvals).
3. Bump the version, tag and release as in section 7.
4. Back-merge `main` into `develop` with a PR the same day; its body must contain
   `Refs #<hotfix issue>`.

## 9. Working with the agents

Shared toolkit committed under `.claude/` — everyone's Claude Code behaves the same. Ticket filing
and routing (`/lw-ticket`, `/lw-route`) live in the leapwell workspace. Skills you run here:

| Skill | When |
|---|---|
| `/lw-start <N>` | Pick up an issue: Definition of Ready, size, branch, plan comment |
| `/lw-fix <N>` | S/M: root cause, failing test, fix, review |
| `/lw-feature <N>` | L: brainstorm, spec, plan, task loop, final review |
| `/lw-pr` | Run checks, fill the template, push the branch, open a draft PR |
| `/lw-release [version]` | Release checklist, notes, signed build check |

Agents the skills dispatch:

| Agent | Role | Writes code? |
|---|---|---|
| `lw-architect` | Design / spec for L (or M with design questions) | No |
| `lw-implementer` | One plan task, TDD, one commit | Yes |
| `lw-reviewer` | Two verdicts: spec compliance + code quality | No |
| `lw-qa` | Regression, negative and offline tests | Tests only |
| `lw-security` | PHI, secrets, auth, storage, logging review | No |
| `lw-release` | Release-readiness checklist | No |

### The task loop (L-size)

1. The main session (you + Claude) holds the decisions and dispatches one task at a time.
2. `lw-implementer` does the task: failing test, minimal code, green, one commit.
3. `lw-reviewer` returns two verdicts: `Spec ✅ | Spec ❌` and `Approved | Changes requested`.
   Both must pass (Spec ✅ + Approved). Otherwise findings go back to the implementer.
4. At most **5 fix rounds** per task; then stop and escalate to a human.
5. Each task's brief, report, verdicts and rulings go into a ledger under
   `.superpowers/sdd/<date>-<slug>/` (local working files, gitignored); the plan's ledger table
   records task, commit and verdicts.
6. **Rulings:** when implementer and reviewer disagree, the main session decides and writes the
   ruling with its reason in the ledger. Anything that changes the approved spec goes to a human.
7. After the last task: a **final whole-branch review** by `lw-reviewer` on the strongest model
   against `origin/develop`, then `/lw-pr`.

### What agents may never do

Merge or approve PRs; push to `main`/`develop`; force-push; skip hooks (`--no-verify`); tag,
upload or publish a release; set priority, milestones or project fields; read or stage prod keys,
keystores, `key.properties`, `google-services.json` or `env*.json` (except `env.example.json`);
print secrets or patient data; file security issues publicly. Subagents never spawn agents.

Guard rails enforce most of this: the `.claude/settings.json` hook (`scripts/sdlc/guard_tool.py`)
blocks the dangerous commands and secret-file access in Claude Code, and the git hooks in
`.githooks/` check commit messages and block staged secrets for everyone.

## 10. One-time developer setup

```sh
sh scripts/setup_dev.sh        # activates .githooks, checks python3 3.11+ and gh
gh auth login                  # GitHub CLI, used by /lw-start, /lw-pr
gh auth refresh -s project     # lets Claude read and update Project #4
```

If you had a personal, untracked `.claude/settings.json`, rename it to
`.claude/settings.local.json` before pulling this change, or git refuses to overwrite it.
Run the SDLC checks any time with `python3 -m unittest discover -s scripts/sdlc/tests -t .`.

Admin setup: [CLAUDE_ADMIN_SETUP.md](CLAUDE_ADMIN_SETUP.md). Filing guide for PM/QA:
`docs/process/TICKETS.md` in [leapwell](https://github.com/Medtronic-LABS/leapwell). Start Claude from the leapwell workspace (clone
leapwell, run `/lw-setup`).
