---
name: lw-feature
description: L-size LEAPWELL feature flow - brainstorm, spec, plan, subagent task loop with review, final review, then lw-pr. For new modules, schema, sync, auth, AI or push work.
argument-hint: <issue-number>
disable-model-invocation: true
---

# L-size feature for issue #$ARGUMENTS

Use when `/lw-start` sized the issue **L**. You are the orchestrating main session: you hold the decisions, dispatch the `lw-*` agents, and keep the human in the loop at each gate. Process reference: `docs/process/SDLC.md`.
Pre-condition: on the `feat/<issue#>-<slug>` branch (run `/lw-start $ARGUMENTS` first if not).

1. **Brainstorm** (superpowers:brainstorming if installed). Otherwise: restate the problem from the issue, ask the user clarifying questions one at a time, and agree the scope and non-goals.

2. **Design / spec.** Dispatch the `lw-architect` agent with the issue number and agreed scope. Write the result to `docs/superpowers/specs/YYYY-MM-DD-<slug>-design.md`.
   **Gate:** a human approves the spec. Do not continue without it.

3. **Plan** (superpowers:writing-plans if installed). Otherwise write `docs/superpowers/plans/YYYY-MM-DD-<slug>.md`: small tasks, each with files, failing test first, the exact test command, and expected result. Commit spec + plan (`docs(<area>): spec and plan for #$ARGUMENTS`).

4. **Task loop** (superpowers:subagent-driven-development if installed). For each task, in order:
   a. Dispatch `lw-implementer` with the task text only (one task, TDD, one commit).
   b. Dispatch `lw-reviewer` on that task's commits. Needs **Spec ✅** and **Approved**; otherwise send findings back to `lw-implementer` and re-review.
   c. For auth / db / sync / scribe / push / logging changes, also dispatch `lw-security`.
   d. Record the task status in the plan (a ledger table: task, commit, review verdicts).
   Dispatch `lw-qa` for regression/negative/offline tests where the plan calls for them.

5. **Final review.** Dispatch `lw-reviewer` (strongest model) on the whole branch diff against `origin/develop` (superpowers:requesting-code-review if installed). Fix and re-review until Spec ✅ / Approved.

6. **Finish** with `/lw-pr` (superpowers:finishing-a-development-branch if installed). L-size PRs need two human reviews.

Never merge, never push to `main`/`develop`, never set priority, never skip hooks.
