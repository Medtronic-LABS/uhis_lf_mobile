---
name: lw-release
description: Walk a LEAPWELL release checklist - version bump PR from pubspec.yaml, readiness check, release notes in English and Bangla, signed build check. Never tags or uploads unless the human explicitly says so.
argument-hint: "[version, e.g. 1.2.0+16]"
disable-model-invocation: true
---

# Release $ARGUMENTS

The human releases; you prepare and check. Process reference: `docs/process/SDLC.md`.

1. **Version.** `pubspec.yaml` is the only version source. Read the current `version:` and the last tag (`git tag --list 'v*' --sort=-v:refname | head -1`). Agree the next version with the user (build number always increases).
   If a bump is needed: create a `chore/<release-issue#>-bump-<semver>-<build>` branch (no `+`, e.g. `chore/42-bump-1.2.0-16`) from `origin/develop`, change only the `version:` line, commit `chore(release): bump version to <version> (#N)`, and open a draft PR with `/lw-pr`. Never bump on `develop` or `main` directly.

2. **Release issue.** Make sure a `[Release] <version>` ticket exists in leapwell (`Medtronic-LABS/leapwell`; file it there with `/lw-ticket` if not) and is routed to a sub-issue here with `/lw-route`.

3. **Readiness.** Dispatch the `lw-release` agent for the checklist (CI on `develop`, milestone scope, open P0/P1 bugs, training verification). Show its report. The `develop` -> `main` release PR body must contain `Refs #<release issue>` (or `Refs Medtronic-LABS/leapwell#<N>`); a hotfix back-merge `main` -> `develop` PR must `Refs #<hotfix issue>`.

4. **Release notes.** Draft from merged PRs / closed issues since the last tag (`gh pr list --base develop --state merged --search "merged:>=<last-tag-date>"`): user-facing language, no internal IDs or patient data. Produce **English and Bangla**, each **500 characters or fewer** - count and show the counts. The user approves the wording.

5. **Build and signer check.** The human runs these on a machine with the release key - one command per app:
   - LEAPWELL (prod): `scripts/release.sh production ""`
   - LW Training: `scripts/release.sh training "" --app-flavor training`

   The empty `""` keeps the current pubspec version (already bumped by the PR in step 1). The script refuses debug signing and runs the signer check. You may explain its output; you never handle the key, `key.properties` or `env*.json`.

6. **Tag and upload - human only.** Only if the human explicitly says "tag it" in this session: show the exact command (`scripts/release.sh production "" --tag`, which creates the local tag `v<version>` such as `v1.2.0+16`, then `git push origin v<version>`) and let them run it. Play Console upload (internal -> closed -> staged prod) is done by the human.

7. **After release.** Remind: tick the release issue, back-merge `main` into `develop` if a hotfix went out, close the milestone.

Never tag, push tags, upload, publish a GitHub release or merge on your own; never set priority.
