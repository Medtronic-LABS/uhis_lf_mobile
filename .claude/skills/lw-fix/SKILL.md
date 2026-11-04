---
name: lw-fix
description: S/M-size LEAPWELL fix flow - systematic debugging, failing test, minimal fix, reviewer agent, then lw-pr. For bugs and small changes inside one feature.
argument-hint: <issue-number>
disable-model-invocation: true
---

# S/M fix for issue #$ARGUMENTS

Use when `/lw-start` sized the issue **S** or **M**. Pre-condition: on the `fix|chore|...|hotfix/<issue#>-<slug>` branch. Process reference: `docs/process/SDLC.md`.

1. **Understand** (superpowers:systematic-debugging if installed). Otherwise: read the issue's steps, reproduce (test, emulator, or by reading the code path), find the root cause - not just the symptom - and state it in one sentence with `path:line`. No fix before a root cause.

2. **M-size only:** write a short design note (approach, files, offline behaviour, risks) and show it to the user before coding; it goes into the PR description later.

3. **Failing test** (superpowers:test-driven-development if installed). Write a test that fails because of the bug (or proves the new behaviour). Run it; confirm it fails for the right reason. `lw-qa` can write it if the user prefers.

4. **Fix.** Minimal change that makes the test pass, following `CLAUDE.md` and the root "Engineering Design Standards". Run the focused tests, then `flutter analyze` on touched files.

5. **Commit.** `fix(<area>): <summary> (#$ARGUMENTS)` - hooks run; never `--no-verify`.

6. **Review.** Dispatch the `lw-reviewer` agent on `git diff origin/develop...HEAD` with the issue number. Needs **Spec ✅** and **Approved**; fix and re-review otherwise. For auth / db / sync / logging changes also dispatch `lw-security`.

7. **PR.** `/lw-pr`.

Never merge, never push to `main`/`develop`, never set priority.
