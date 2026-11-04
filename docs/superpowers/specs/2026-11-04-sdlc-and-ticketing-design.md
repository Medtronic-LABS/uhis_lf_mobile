# LW-SDLC + GitHub ticketing — design

Date: 2026-11-04 · Repo: `Medtronic-LABS/uhis_lf_mobile` · Owner: repo admins

## Intent

Give the LEAPWELL team one written, enforced software-development process that works
with multi-agent (Claude) development, and move ticket management from Jira to GitHub
Issues + the org Project "LeapWell" (#4). Everyone — devs, QA, PM — files tickets through
Claude (Claude Code CLI / Desktop "Code", or Claude Desktop / claude.ai chat), and Claude
interviews them before anything is created.

## Decisions taken by the owner (2026-11-04)

| # | Decision |
|---|---|
| D1 | Scope: ticketing **and** the full SDLC (process doc, shared agents/skills/hooks, CI gates). |
| D2 | **Jira LEAP is retired** for this app. GitHub Issues is the only tracker. |
| D3 | References use GitHub `#N`: branches `feat/123-slug`, PRs must say `Closes #N` / `Refs #N`. |
| D4 | The overnight run may push a branch and open a **draft** PR. It must **not** change GitHub settings, labels, project fields or branch protection — those ship as scripts a human runs. |

## Goals

1. A short canonical process doc (`docs/process/SDLC.md`) every dev, QA and PM can follow.
2. Ticket intake through an `lw-ticket` skill that asks type-specific questions, checks
   duplicates and PHI, previews, and creates only after an explicit "yes" — identical
   behaviour in Claude Code and claude.ai/Desktop chat (same `SKILL.md`).
3. GitHub-side enforcement that does not depend on Claude being used: issue forms with the
   same required fields, blank issues disabled, an issue-check Action, a PR-check Action,
   CI gates, CODEOWNERS, and a branch-protection script.
4. A committed, shared multi-agent toolkit (plugin) so every dev's Claude behaves the same:
   role agents, workflow skills, and safety hooks.

## Non-goals

- Changing app code under `lib/`.
- Migrating existing Jira tickets automatically (a manual migration note only).
- Play Console automation (already tracked in `RELEASE_PLAN.md`).
- Running any GitHub admin script (D4).

## Anti-goals (would make this a failure even if it "works")

- PHI, credentials, tokens, backend secrets or unscrubbed device logs ending up in public
  issues (**the repo is public**).
- A process so heavy that S-size fixes need a spec — ceremony scales with size.
- Two sources of truth for skill text (Code plugin vs chat upload must be the same file).
- Agents that merge, release, set priority, or touch prod keys.

## Constraints

- The repo is **public**: every issue/PR is world-readable.
- Bangladesh context: phone numbers `01XXXXXXXXX` / `+8801XXXXXXXXX`, NID 10/13/17 digits.
- Existing CI: `android-apk.yml` runs `flutter analyze` and `flutter test` with
  `continue-on-error: true`, only for PRs to `main`. `release.yml` builds on `v*` tags.
- Flutter 3.44.8 in CI. Team `@Medtronic-LABS/leapfrogging` has write access.
- Existing labels: bug, documentation, duplicate, enhancement, good first issue,
  help wanted, invalid, question, wontfix, refactor, tech-debt, chore.
- Project #4 fields: Status (Backlog, Ready, In progress, In review, Done), Priority
  (no options), Size (XS–XL), Estimate, Start/Target date.
- Five agent worktrees are committed as gitlinks under `.claude/worktrees/`; `.claude/`
  otherwise only ignores `settings.local.json`. `env.training.json` is not in `.gitignore`.

## Design

### 1. Process (`docs/process/SDLC.md`)

- **Sizes:** S (≤ ~50 lines, no new behaviour) → issue, branch, fix + test, PR, 1 review.
  M (new behaviour inside one feature) → design section in the issue/PR, implement, reviewer
  agent, human review. L (new module, schema, sync, auth, AI, push) → spec + plan under
  `docs/superpowers/`, subagent task loop with ledger, final review on the strongest model,
  2 human reviews.
- **Issue lifecycle (Project Status):** Triage → Backlog → Ready → In progress → In review
  → QA → Done. Definition of Ready and Definition of Done are written out.
- **Branching:** `feat|fix|chore|docs/<issue#>-<slug>` → PR to `develop` → training build
  QA → `develop`→`main` PR → `v*` tag → Play (internal → closed → staged prod).
  Hotfix: branch from `main`, PR to `main`, back-merge to `develop`.
- **Versioning:** `pubspec.yaml` is the only version source; bump via PR before tagging.
- **Human-only gates:** approving specs, setting priority, merging, releasing, Play upload,
  prod keys/secrets, security exceptions.

### 2. Ticket intake — `lw-ticket` skill

One `SKILL.md` (plus reference files) used in both surfaces. Flow: pick type
(bug / feature / task / release) → duplicate search → one question at a time per type →
PHI/secret scrub of the draft → propose labels/area/priority/size → full preview → create
only on explicit yes → add to Project #4 with Status = Triage → return the link.
Security issues are redirected to private vulnerability reporting, never filed publicly.
In Claude Code it uses `gh`; in chat it uses the GitHub connector. The body it writes uses
**the same headings as the issue forms**, so the issue-check Action validates both paths.

### 3. GitHub-side enforcement

- Issue forms (`bug`, `feature`, `task`, `release`) + `config.yml` with blank issues off
  and a security contact link.
- `issue-check` workflow → `scripts/github/check_issue.py`: required sections per type
  present and non-empty; PHI/secret patterns; on failure adds `status:needs-info` and
  comments what is missing (never echoing the matched secret); on pass removes it.
- `pr-check` workflow → `scripts/github/check_pr.py`: PR body references an issue
  (`Closes|Fixes|Resolves|Refs #N`); template checklist present. Fails the check otherwise.
- CI workflow on PRs to `develop` and `main`: analyze, test, gitleaks secret scan; blocking
  where the baseline allows (see plan), documented ratchet otherwise.
- `.github/CODEOWNERS` (team default; admins on sensitive paths).
- `.github/pull_request_template.md`.
- Scripts a human runs (D4): `scripts/github/sync_labels.sh` (from `.github/labels.yml`),
  `scripts/github/setup_project.sh` (Priority/Status options, Iteration),
  `scripts/github/protect_branches.sh`. All default to dry-run.

### 4. Shared multi-agent toolkit — committed `.claude/`

Committed directly under `.claude/agents`, `.claude/skills` and `.claude/settings.json`
(hooks only). Claude Code (CLI and Desktop "Code") loads project agents/skills/hooks for
anyone who opens the repo — no plugin install step. (Builder's call: a plugin marketplace
was considered and rejected — it adds an install step and only helps outside this repo.)
Personal settings stay in the gitignored `.claude/settings.local.json`.

- Agents: `lw-architect`, `lw-implementer`, `lw-reviewer`, `lw-qa`, `lw-security`,
  `lw-release` (role, tools, model tier, hard limits).
- Skills: `lw-ticket`, `lw-start` (pick up an issue), `lw-feature` (L flow), `lw-fix`
  (S/M flow), `lw-pr`, `lw-release`.
- Hooks: block `git push` to `main`/`develop`, `--no-verify`, force-push; block reading
  or staging `env*.json` (except `env.example.json`), `key.properties`, keystores,
  `google-services.json`.
- Git hooks (`.githooks/`, activated by `scripts/setup_dev.sh`): commit-msg requires
  `#N` or a Conventional Commit type; pre-commit blocks staged secrets/env files.

### 5. Chat surface (claude.ai / Desktop)

`scripts/github/package_skill.sh` zips the same `lw-ticket` skill for org-admin upload.
`docs/process/CLAUDE_ADMIN_SETUP.md` covers provisioning the skill and the GitHub
connector. `docs/process/TICKETS.md` is the 1-page guide for PM/QA.

### 6. Repo hygiene

Untrack the committed `.claude/worktrees/*` gitlinks and ignore `.claude/worktrees/`;
ignore `env.*.json` except `env.example.json`; update `CLAUDE.md` to point at the process
and plugin; retire Jira references.

## Left to the builder

Exact question wording, label colours, agent prompt text, regexes (with tests), CI step
details — following the constraints above.
