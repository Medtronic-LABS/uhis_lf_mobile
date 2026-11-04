---
name: lw-pr
description: Open a LEAPWELL draft pull request - run the checks, fill the PR template with Closes #N, push the feature branch and create a draft PR to develop (hotfix to main).
argument-hint: "[issue-number]"
disable-model-invocation: true
---

# Open a draft PR

1. **Branch and issue.** `git branch --show-current` must match `<type>/<issue#>-<slug>` - take the issue number from it (or from `$ARGUMENTS`). Refuse on `main` / `develop`.
   Base: `develop`; `hotfix/*` -> `main` (and remind the user to back-merge `main` into `develop` after release).

2. **Checks** (report each with the result, do not hide failures):
   - `python3 -m unittest discover -s scripts/sdlc/tests -t .`
   - `flutter analyze` - error count must not exceed the CI budget in `docs/process/SDLC.md`.
   - `flutter test <test files related to the change>` (and the full `flutter test` for M/L) - failures must not exceed the budget.
   - `git status --porcelain` clean; `git log origin/<base>..HEAD --oneline` shows only this issue's commits.

3. **Body.** Fill `.github/pull_request_template.md` into a temp file. Write it with the Write tool (preferred) or a quoted heredoc (`<<'EOF'`) - never an unquoted heredoc or `echo` of user text:
   - First line `Closes #<N>` (or `Refs #<N>` if it does not fully resolve the issue).
   - Summary (what and why, 2-5 lines; M-size: include the design note), Size (tick one), Test evidence (commands + results from step 2), Screenshots (test data only), Risk & rollback, Definition of Done ticked honestly - leave unticked what is not done.
   - No patient data, secrets, tokens or raw logs.
   Show the title and body to the user before creating.

4. **Push and create** (after the user's OK):
   ```
   git push -u origin <branch>
   gh pr create --draft --repo Medtronic-LABS/uhis_lf_mobile --base develop --head <branch> --title "<type>(<area>): <summary> (#N)" --body-file <tmpfile>
   ```
   (`--base main` for hotfix). Report the PR link. Marking it ready for review, requesting reviewers and merging are the human's steps.

Never merge, never push to `main`/`develop`, never force-push, never skip hooks.
