# Task - questions and body

Matches the GitHub form `task.yml` (template `task`, type label `chore`, title prefix `[Task] `).
For chores, refactors, tech debt and internal work. Ask one at a time, skipping what is known.

| # | Heading (field id) | Ask | Notes |
|---|---|---|---|
| 1 | What (`what`) | "What needs doing?" | Concrete and bounded ("Upgrade go_router to 15.x", not "clean up routing"). |
| 2 | Why now (`why_now`) | "Why does it need doing now?" | Deadline, dependency, blocked work, deprecation. |
| 3 | Risk if not done (`risk`) | "What happens if we don't do it?" | Derive if obvious and confirm. |

## Suggested priority (never applied as a label)
- **P1** - blocks a release or other work now.
- **P2** - needed within the next few sprints.
- **P3** - opportunistic clean-up.

## Body template (headings exact)

```markdown
### What

...

### Why now

...

### Risk if not done

...

### Suggested priority

P3 (suggestion only - set at triage): ...

### Privacy check

- [x] This issue contains no patient/member data, names, phone numbers, IDs, credentials, tokens or unscrubbed logs (this repo is public)
```
