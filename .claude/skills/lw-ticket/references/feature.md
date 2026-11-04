# Feature - questions and body

Matches the GitHub form `feature.yml` (template `feature`, type label `enhancement`, title prefix `[Feature] `).
Ask in this order, one at a time, skipping what is already known.

| # | Heading (field id) | Ask | Choices / notes |
|---|---|---|---|
| 1 | Problem (`problem`) | "What problem are you trying to solve? What happens today?" | Usually in the first message. Focus on the pain, not the solution. |
| 2 | User (`user`) | "Who is this for?" | SK (community health worker) / Supervisor / Clinician / Admin |
| 3 | Proposed solution (`solution`) | "What would you like the app to do?" | Fine to be rough; restate it back in one or two sentences. |
| 4 | Acceptance criteria (`acceptance`) | "How will we know it's done? I'll draft 'Given / when / then' checks from what you said - tell me what to change." | Draft 2-5 checkboxes yourself, then confirm. Include an offline case when relevant. |
| 5 | Programme (`programme`) | "Which health programme is this for?" | ANC / PNC / NCD / IMCI/iCCM / TB / EPI / Nutrition / Family planning / Eye care / Cross-cutting. Derive from the problem and confirm. |
| 6 | Offline behaviour (`offline`) | "What should happen when the phone has no internet? Should it work offline and sync later?" | Default proposal: "Works fully offline; syncs on next connection" - confirm. |
| 7 | Designs (`designs`) | Only if mentioned: "Any mockup or design link?" | Optional. Links only; mockups must use made-up data. |

## Suggested priority (never applied as a label)
- **P1** - blocks a pilot/rollout commitment or a clinical-safety gap.
- **P2** - planned improvement with a clear user benefit.
- **P3** - nice to have.

## Body template (headings exact; omit `### Designs` if empty)

```markdown
### User

SK (community health worker)

### Problem

...

### Proposed solution

...

### Acceptance criteria

- [ ] Given ..., when ..., then ...
- [ ] Given no internet, when ..., then ...

### Programme

NCD

### Offline behaviour

Works fully offline; syncs on next connection.

### Designs

<link, or omit this section>

### Suggested priority

P2 (suggestion only - set at triage): ...

### Privacy check

- [x] This issue contains no patient/member data, names, phone numbers, IDs, credentials, tokens or unscrubbed logs (this repo is public)
```

Programme values must be copied exactly: `ANC`, `PNC`, `NCD`, `IMCI/iCCM`, `TB`, `EPI`, `Nutrition`, `Family planning`, `Eye care`, `Cross-cutting`.
