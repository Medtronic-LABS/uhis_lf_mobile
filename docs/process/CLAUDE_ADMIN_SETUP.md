# Admin setup: Claude org and GitHub

One-time steps that make the SDLC in [SDLC.md](SDLC.md) work for everyone. Ticket filing, the
`lw-ticket` skill and its Claude-org / connector setup now live in [leapwell](https://github.com/Medtronic-LABS/leapwell). Nothing here was run
by the overnight build: GitHub settings and Claude org settings are changed only by people.

| Who | Section |
|---|---|
| GitHub **repo admin(s)** of `Medtronic-LABS/uhis_lf_mobile` (and an org owner where noted) | 1, 2, 3, 4 |
| Every developer | 5 |

## Rollout order

GitHub serves `config.yml` (the issue chooser) only from the default branch (`main`). Roll out in
this order:

1. Merge this PR to `develop`.
2. The next `develop` -> `main` release PR brings the issue chooser (links to leapwell) live.
3. Run `scripts/github/protect_branches.sh` (dry-run first, then `--apply`), only after the
   required checks have run once on both `develop` and `main`.
4. Before applying protection, every open PR needs a GitHub issue and `Refs #N` (or
   `Refs Medtronic-LABS/leapwell#N`) in its body, or must be merged or closed. List them with
   `gh pr list --state open`.

## 1. Labels, project fields and branch protection

The scripts default to a **dry-run** that only prints what they would do. Read the output, then
re-run with `--apply`. Needs `gh` signed in as a repo admin (`gh auth refresh -s project` for the
project script).

```sh
bash scripts/github/sync_labels.sh            # dry-run: labels from .github/labels.yml
bash scripts/github/sync_labels.sh --apply
bash scripts/github/setup_project.sh          # Project #4: Priority options, Sprint iteration
bash scripts/github/setup_project.sh --apply
bash scripts/github/protect_branches.sh       # main: 2 approvals, develop: 1, required checks
bash scripts/github/protect_branches.sh --apply
```

Required check names (`pr-check`, `sdlc-scripts`, `secret-scan`, `flutter`, `build-apk`) appear
in the branch-protection UI picker only after they have run once; `protect_branches.sh` sets them
by name through the API regardless. Until the workflows are on the target branch and have run,
PRs will wait on those checks.

`setup_project.sh` never edits **Status** (the API replaces the whole option list and can wipe
item values). In the UI: Project → Settings → Status → add `Triage` and drag it to the top; add
`QA` between `In review` and `Done`. Target order: Triage, Backlog, Ready, In progress, In
review, QA, Done. If the Sprint iteration call errors, create it in the UI (Iteration, 2 weeks).

## 2. Project #4 built-in workflows

Project → Workflows (UI only), enable:

| Workflow | Setting |
|---|---|
| Auto-add to project | filter `repo:Medtronic-LABS/uhis_lf_mobile is:issue` (issues only; PRs link via `Closes #N`) |
| Item added to project | set Status = Triage |
| Item closed | set Status = Done |
| Pull request merged | set Status = Done |
| Item reopened | set Status = In progress |

## 3. Private vulnerability reporting

Repo Settings → Code security → enable **Private vulnerability reporting**. The issue chooser
and `lw-security` both send security reports to
<https://github.com/Medtronic-LABS/uhis_lf_mobile/security/advisories/new>; it only works once this is on.

## 4. Owner follow-ups

- **`pr-check` on forks:** it runs on `pull_request`, which is fine for branches in this repo.
  Moving it to `pull_request_target` (so fork PRs get the check with a trusted token) is a
  follow-up; do it only with a reviewed workflow that never checks out or runs PR code.
- **Fork PRs and `build-apk`:** fork PRs cannot pass `build-apk` (no secrets are exposed to forks).
  Acceptable for the team repo, where contributors push branches here.
- **First full-history secret scan:** CI scans only each PR's commits. Run gitleaks once over the
  full history (`gitleaks git --redact`) and rotate anything it finds.
- **Ratchet the budgets:** as tests and analyzer errors get fixed, lower `ANALYZE_ERROR_BUDGET`
  and `TEST_FAILURE_BUDGET` in `.github/workflows/ci.yml` (see SDLC.md section 6).
- **Jira freeze date:** set it in [JIRA_RETIREMENT.md](JIRA_RETIREMENT.md).

## 5. Every developer, once

- If you had a personal, untracked `.claude/settings.json` in your checkout, rename it to
  `.claude/settings.local.json` **before** pulling the branch that adds the shared
  `.claude/settings.json`; otherwise git refuses to overwrite it. Personal permissions belong in
  `settings.local.json` (gitignored).
- Then follow SDLC.md section 10 (`scripts/setup_dev.sh`, `gh auth login`, `gh auth refresh -s project`).
