---
name: lw-start
description: Pick up a LEAPWELL GitHub issue - check Definition of Ready, size it S/M/L, create the type/<issue#>-<slug> branch from develop, and post the plan on the issue.
argument-hint: <issue-number>
disable-model-invocation: true
---

# Start work on issue #$ARGUMENTS

Process reference: `docs/process/SDLC.md` (sizes, Definition of Ready, branching). Repo: `Medtronic-LABS/uhis_lf_mobile`.

1. **Read the issue.** `gh issue view $ARGUMENTS --repo Medtronic-LABS/uhis_lf_mobile --json number,title,labels,body,comments,assignees,milestone,state`
   If no number was given, ask for one. If the issue is closed, stop.

2. **Definition of Ready.** Report each as ok / missing:
   - Required sections for its type are filled (the leapwell ticket is complete); bug has steps to reproduce, feature has acceptance criteria.
   - Triaged: has a `prio:*` label (set by a human - you never set it) and an `area:*` label.
   - Not `status:blocked` / `status:needs-design`; open questions answered.
   If something is missing, say what, and ask whether to continue anyway. Do not edit the issue to make it look ready.

3. **Size** using `docs/process/SDLC.md`: S (small, no new behaviour), M (new behaviour inside one feature), L (new module, schema, sync, auth, AI, push). Read the code the issue touches before deciding; give a one-line reason.

4. **Branch.** Prefix from type: `bug` -> `fix`, `enhancement` -> `feat`, `chore` -> `chore` (or `refactor` / `docs` / `test` if more accurate); a P0 prod bug the team agreed to hotfix -> `hotfix` from `main`.
   Name: `<prefix>/<issue#>-<short-kebab-slug>` (e.g. `fix/123-sync-stuck-90`).
   ```
   git fetch origin
   git switch -c <branch> origin/develop      # hotfix: origin/main
   ```
   If the branch already exists, switch to it instead.

5. **Plan comment.** Draft a short comment: size + reason, approach (3-6 bullets), files likely touched, test plan, and the next step (`/lw-fix` for S/M, `/lw-feature` for L). No patient data, secrets or raw logs. Show it, and post only after the user says yes:
   `gh issue comment $ARGUMENTS --repo Medtronic-LABS/uhis_lf_mobile --body-file <tmpfile>`
   Write it with the Write tool (preferred) or a quoted heredoc (`<<'EOF'`) - never an unquoted heredoc or `echo` of user text.
   Offer to assign the issue to the user (`gh issue edit $ARGUMENTS --repo Medtronic-LABS/uhis_lf_mobile --add-assignee @me`). Moving the Project card to "In progress" is the user's call.

6. **Next.** S/M -> `/lw-fix $ARGUMENTS`. L -> `/lw-feature $ARGUMENTS`.

Never set priority, never push to `main`/`develop`, never skip hooks.
