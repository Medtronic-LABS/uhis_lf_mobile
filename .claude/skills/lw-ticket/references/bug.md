# Bug - questions and body

Matches the GitHub form `bug.yml` (template `bug`, type label `bug`, title prefix `[Bug] `).
Ask in this order, one at a time, skipping what is already known. Target: 10 questions or fewer.

| # | Heading (field id) | Ask | Choices / notes |
|---|---|---|---|
| 1 | Actual behaviour (`actual`) | "What went wrong? Tell me in your own words." | Usually the user's first message - confirm, don't re-ask. Capture any exact error text (scrubbed). |
| 2 | Screen or feature (`screen`) | "Which screen or part of the app were you in?" | Often derivable from 1. Examples: Login, Home/worklist, Household, Visit (ANC/NCD/...), AI Scribe, Sync, Tasks. |
| 3 | Steps to reproduce (`steps`) | "What did you tap or do, step by step, right before it happened?" | Write as a numbered list. Use roles, not people ("Open a test household"). |
| 4 | Expected behaviour (`expected`) | "What did you expect to happen instead?" | Derive if obvious ("should save") and confirm. |
| 5 | Frequency (`frequency`) | "How often does it happen?" | Always / Often / Sometimes / Once |
| 6 | Impact (`impact`) | "How much does it get in the way?" | SKs cannot work / Workaround exists / Cosmetic. Derive from 1 (crash on login = SKs cannot work; misaligned text = Cosmetic) and confirm. If a workaround exists, note it under Actual behaviour. |
| 7 | Build flavor (`build_flavor`) | "Which app was it - the main LEAPWELL app, LW Training, or a dev build?" | prod (LEAPWELL) / training (LW Training) / dev |
| 8 | App version (`app_version`) | "Which app version? It's in Settings > About, like 1.1.0+15." | In Claude Code, offer to read it with adb (see SKILL.md). |
| 9 | Device and Android version (`device`) | "Which phone model and Android version?" | e.g. "Samsung Galaxy A14, Android 13". adb can read both. |
| 10 | Logs or screenshots (`logs`) | Only if the user mentions logs/screens: "Any error message or log lines to include?" | Optional. Scrubbed excerpt only, at most ~30 lines. Screenshots are added on GitHub after creation. |

## Suggested priority (never applied as a label)
- **P0** - Impact "SKs cannot work" on prod, Always/Often (e.g. cannot log in, cannot sync, data loss).
- **P1** - "SKs cannot work" on training/dev, or Sometimes/Once on prod; wrong clinical result or alert.
- **P2** - Workaround exists.
- **P3** - Cosmetic.

## Body template (headings exact; omit `### Logs or screenshots` if empty)

```markdown
### App version

1.1.0+15

### Build flavor

training (LW Training)

### Device and Android version

<model>, Android <n>

### Screen or feature

<screen>

### Steps to reproduce

1. ...
2. ...
3. ...

### Expected behaviour

...

### Actual behaviour

...

### Frequency

Sometimes

### Impact

Workaround exists

### Logs or screenshots

<scrubbed excerpt, or omit this section>

### Suggested priority

P2 (suggestion only - set at triage): workaround exists.

### Privacy check

- [x] This issue contains no patient/member data, names, phone numbers, IDs, credentials, tokens or unscrubbed logs (this repo is public)
```

Dropdown values must be copied exactly: Build flavor `prod (LEAPWELL)`, `training (LW Training)`, `dev`; Frequency `Always`, `Often`, `Sometimes`, `Once`; Impact `SKs cannot work`, `Workaround exists`, `Cosmetic`.
