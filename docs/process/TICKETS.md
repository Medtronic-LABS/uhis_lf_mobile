# Filing a LEAPWELL ticket

For QA, PM and anyone else reporting a problem or asking for something in the LEAPWELL
(Apon Sushashthya) app. Tickets live in GitHub Issues; Jira is no longer used for this app.

## Two ways to file

- **Claude Desktop or claude.ai chat:** just say *"file a bug"* (or "I want to request a feature").
  The `lw-ticket` skill takes over and interviews you.
- **Claude Code:** type `/lw-ticket`.

Claude asks one question at a time, checks whether the problem is already reported, shows you
the full ticket, and creates it **only after you say yes**. You get the link back.

## What Claude will ask

- **Bug:** app version, build (prod / training / dev), phone and Android version, which screen,
  the steps, what you expected, what happened, how often, and how badly it blocks work.
- **Feature:** who needs it, the problem today, the idea, how we will know it works, which
  programme (ANC, NCD, …), and what should happen offline.
- **Task:** what, why now, and the risk if we don't do it.

If you don't know something (for example the app version), say so; Claude helps you find it or
marks it unknown. It also suggests a priority, but the team sets the real priority at triage.

## Privacy rule — this repository is public

Anyone on the internet can read every ticket. Never include patient or member names, phone
numbers, IDs, addresses, passwords, tokens or raw logs. Claude replaces these with placeholders
and tells you what it removed. A security problem (for example a login bypass, or one user seeing
another's data) is **not** filed as a ticket: report it privately at
<https://github.com/Medtronic-LABS/uhis_lf_mobile/security/advisories/new> and tell the team lead.

## Screenshots

Claude cannot attach images. After the ticket is created, open the link and drag your
screenshot into a comment — only screenshots from **test data**, never a real patient.

## No Claude? Use the web forms

Open <https://github.com/Medtronic-LABS/uhis_lf_mobile/issues/new/choose>, pick Bug report,
Feature request, Task or Release, fill every required field and tick the privacy box.

## What happens next

The team triages new tickets **twice a week**: sets priority, area, size and owner, and moves the
ticket on the LeapWell board (Triage → Backlog → Ready → … → Done). If something is missing, a bot
adds `status:needs-info` and comments what to add; edit the ticket and the label goes away.

## Labels

| Label | Meaning |
|---|---|
| `bug` / `enhancement` / `chore` / `release` | Bug, feature request, internal task, release tracking |
| `area:*` | Part of the app (e.g. `area:sync`, `area:visit`, `area:auth`) |
| `env:prod` / `env:training` / `env:dev` | Which build the bug was seen in |
| `prio:P0` | Drop everything: health workers cannot work |
| `prio:P1` | Fix this sprint |
| `prio:P2` / `prio:P3` | Planned / nice to have |
| `status:needs-info` | Waiting for the reporter to complete the ticket |
| `status:blocked` / `status:needs-design` | Waiting on something else / on a design decision |
