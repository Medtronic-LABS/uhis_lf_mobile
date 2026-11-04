# Admin setup: Claude org and GitHub

One-time steps that make the SDLC in [SDLC.md](SDLC.md) work for everyone. Nothing here was run
by the overnight build: GitHub settings and Claude org settings are changed only by people.

| Who | Section |
|---|---|
| Claude org **Owner** (Team / Enterprise plan) | 1, 2 |
| GitHub **repo admin(s)** of `Medtronic-LABS/uhis_lf_mobile` (and an org owner where noted) | 3, 4, 5, 6 |
| Every developer | 7 |

## 1. Upload the `lw-ticket` skill to the Claude org

So PM/QA can say "file a bug" in claude.ai or Claude Desktop chat.

1. From a clean checkout of `main`: `bash scripts/github/package_skill.sh`.
   It writes `dist/skills/lw-ticket.zip` (folder `lw-ticket/` at the zip root, matching the skill
   name; `dist/` is gitignored). It is the same `SKILL.md` Claude Code uses — never edit the zip.
2. claude.ai → organisation settings → Skills → upload the zip as an org-wide skill. Per
   Anthropic's help article "Managing skills as an admin", Owners can add org-wide skills by
   uploading a `.zip` whose folder name matches the skill name; users can toggle it off but not
   delete it. Exact menu names may differ from this description.
3. After any change to `.claude/skills/lw-ticket/`, re-run the script and upload the new zip.

## 2. Add the GitHub connector in claude.ai — verify first

The chat skill creates issues through a GitHub connector.

1. claude.ai → organisation settings → Connectors → add a **custom connector** with URL
   `https://api.githubcopilot.com/mcp/` (GitHub's hosted MCP server).
2. Each user then connects it with **their own** GitHub account (OAuth), so issues are created
   under their name with their permissions.

**Not verified:** OAuth for this server through claude.ai custom connectors has not been tested
for our org. The `Medtronic-LABS` GitHub org may also need an org owner to approve the
connector's OAuth app (GitHub → org settings → Third-party access). **Test with one user first:**
file a test ticket, check it appears, then close it. If the connector does not work, nothing
breaks — `lw-ticket` falls back to showing the finished ticket as Markdown plus a prefilled
issue-form link the user opens and submits. Tell users which mode to expect.

## 3. Labels, project fields and branch protection

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

Apply `protect_branches.sh` only once the workflows behind its required checks (`pr-check`,
`sdlc-scripts`, `secret-scan`, `flutter`, `build-apk`) are merged and have reported on a PR;
otherwise PRs wait for checks that never arrive.

`setup_project.sh` never edits **Status** (the API replaces the whole option list and can wipe
item values). In the UI: Project → Settings → Status → add `Triage` and drag it to the top; add
`QA` between `In review` and `Done`. Target order: Triage, Backlog, Ready, In progress, In
review, QA, Done. If the Sprint iteration call errors, create it in the UI (Iteration, 2 weeks).

## 4. Project #4 built-in workflows

Project → Workflows (UI only), enable:

| Workflow | Setting |
|---|---|
| Auto-add to project | filter `repo:Medtronic-LABS/uhis_lf_mobile is:issue` |
| Item added to project | set Status = Triage |
| Item closed | set Status = Done |
| Pull request merged | set Status = Done |
| Item reopened | set Status = In progress |

## 5. Private vulnerability reporting

Repo Settings → Code security → enable **Private vulnerability reporting**. The issue chooser,
`lw-ticket` and `lw-security` all send security reports to
<https://github.com/Medtronic-LABS/uhis_lf_mobile/security/advisories/new>; it only works once this is on.

## 6. Owner follow-ups

- **`pr-check` on forks:** it runs on `pull_request`, which is fine for branches in this repo.
  Moving it to `pull_request_target` (so fork PRs get the check with a trusted token) is a
  follow-up; do it only with a reviewed workflow that never checks out or runs PR code.
- **First full-history secret scan:** CI scans only each PR's commits. Run gitleaks once over the
  full history (`gitleaks git --redact`) and rotate anything it finds.
- **Ratchet the budgets:** as tests and analyzer errors get fixed, lower `ANALYZE_ERROR_BUDGET`
  and `TEST_FAILURE_BUDGET` in `.github/workflows/ci.yml` (see SDLC.md section 6).
- **Jira freeze date:** set it in [JIRA_RETIREMENT.md](JIRA_RETIREMENT.md).

## 7. Every developer, once

- If you had a personal, untracked `.claude/settings.json` in your checkout, rename it to
  `.claude/settings.local.json` **before** pulling the branch that adds the shared
  `.claude/settings.json`; otherwise git refuses to overwrite it. Personal permissions belong in
  `settings.local.json` (gitignored).
- Then follow SDLC.md section 10 (`scripts/setup_dev.sh`, `gh auth login`, `gh auth refresh -s project`).
