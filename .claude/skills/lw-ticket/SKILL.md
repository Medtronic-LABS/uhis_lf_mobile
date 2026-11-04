---
name: lw-ticket
description: File a LEAPWELL (uhis_lf_mobile) ticket on GitHub through a short interview. Use whenever someone wants to file, create, raise, report or log a bug, ticket, issue, feature request, task, chore or release for the LEAPWELL / Apon Sushashthya app - checks for duplicates, asks one question at a time, removes patient data and secrets, previews, and creates the GitHub issue only after an explicit yes.
---

# LEAPWELL ticket intake

You help a developer, QA tester or PM file a GitHub issue in **Medtronic-LABS/uhis_lf_mobile**.
The repository is **public**: anything filed is readable by anyone on the internet.
Jira is retired; GitHub Issues + the org Project "LeapWell" (#4) are the tracker.

This file works in two places. Detect which one you are in from the tools you have:
- **Claude Code** (you can run shell commands): use `gh` and, where available, the `AskUserQuestion` tool for choice questions.
- **Chat** (claude.ai / Claude Desktop): ask conversationally; use the GitHub connector's tools. On the official GitHub MCP server the create tool is `issue_write` with method `create`, and search is `search_issues`; other connectors name them differently. If there is no GitHub tool, use the **No-tool fallback** below.

## Interview rules

- Ask **one question at a time**, in plain language. No jargon for PM/QA ("Which screen were you on?", not "Which route?").
- For dropdown fields, offer the form's options as choices (with `AskUserQuestion` in Claude Code: 2-4 options; the tool adds "Other" itself).
- **Derive before you ask.** Pull everything you can from what the user already said, then confirm in one line ("Sounds like it happens every time - right?") instead of asking again.
- Skip optional fields unless the user brings them up. A bug should take **10 questions or fewer**.
- If an answer is vague ("it crashed"), ask one follow-up for the concrete step or message, then move on.
- Never invent facts. If the user does not know something (e.g. app version), help them find it (see "Device info" below) or write `Unknown - reporter could not check` and say so in the preview.

## Flow

### 1. Type
Ask what they want to file unless it is obvious from their message, then confirm:
- **Bug** - something in the app is broken -> `references/bug.md`
- **Feature** - a new capability or improvement -> `references/feature.md`
- **Task** - chore, refactor, tech debt, internal work -> `references/task.md`
- **Release** - track a release (maintainers only) -> `references/release.md`

Read the matching reference file now; it holds the questions, choices, derivation rules and the exact body template.

**Security stop.** If the report is a security vulnerability (login/PIN bypass, one user seeing another's data, tokens or keys exposed, data sent unencrypted) or says real patient data is already exposed somewhere, **stop**. Do not file a public issue and do not repeat the details back. Tell the user to report it privately at https://github.com/Medtronic-LABS/uhis_lf_mobile/security/advisories/new and to tell the team lead. If they pasted a real secret into this conversation, tell them to rotate it.

### 2. Duplicate check
Before the interview, take 2-3 keywords from the user's first description (screen, symptom, feature name) and search **open** issues:
- Claude Code: `gh issue list --repo Medtronic-LABS/uhis_lf_mobile --state open --search '<keywords>' --limit 5 --json number,title,url`
  (single-quote the keywords, as with the title; plain words only - no quotes or symbols)
- Chat: the connector's search tool with `repo:Medtronic-LABS/uhis_lf_mobile is:issue is:open <keywords>`.

Show up to 5 likely matches as `#N - title` and ask "Is it the same as one of these?"
- **Same:** offer to add a comment to that issue instead (new device, version, steps or frequency). Draft the comment, apply the privacy scrub, preview, and post only after "yes" (`gh issue comment <N> --repo Medtronic-LABS/uhis_lf_mobile --body-file <file>`, or the connector's add-comment tool). Then stop.
- **Not the same / no matches:** continue.

### 3. Interview
Ask the questions from the reference file in its order, skipping anything already answered or derived.

**Device info (Claude Code, bugs only).** If `adb devices` lists a device, ask: "A phone is connected - may I read the app version and device model from it?" Only with a yes, run:
- `adb shell dumpsys package com.medtroniclabs.uhis_next | grep -E 'versionName|versionCode'` (LEAPWELL prod; use `com.medtroniclabs.uhis_next.training` for LW Training)
- `adb shell getprop ro.product.model`
- `adb shell getprop ro.build.version.release`

Format the version as `<versionName>+<versionCode>` (e.g. `1.1.0+14`) and confirm it with the user. Never pull logcat into the issue. If the user wants logs included, take only the few relevant lines and scrub them per `references/privacy.md`.

### 4. Privacy scrub
Apply `references/privacy.md` to the **whole draft** (title, every section, comments). Replace anything sensitive with a placeholder such as `<member-id>`, `<name>`, `<phone>`, and tell the user in one line what you removed ("I replaced a phone number and a member ID with placeholders."). Only then tick the Privacy check box in the body.

**Screenshots:** you cannot attach images. Tell the user they can drag screenshots into the issue on GitHub after it is created - only if the screenshot shows training/test data and no real patient or member details.

### 5. Labels
- Always the **type label**: `bug`, `enhancement` (feature), `chore` (task) or `release`.
- Propose **one** `area:*` label from the table below, and confirm it.
- Bugs: the `env:*` label from Build flavor - prod -> `env:prod`, training -> `env:training`, dev -> `env:dev`.
- **Priority is a suggestion only.** Propose `prio:P0`-`prio:P3` with a one-line reason (rules in the reference file). Do **not** add a `prio:*` label; write the suggestion in the body's `### Suggested priority` section. Say clearly that the team sets priority at triage - never tell the user priority is set.

| Area label | Use when the ticket is about |
|---|---|
| `area:auth` | Login, PIN, biometric, lock, session |
| `area:sync` | Offline sync, upload, "pending" records |
| `area:db` | Local database, data missing after restart/update |
| `area:visit` | Visit flow, assessments, forms (ANC/PNC/NCD/TB/IMCI ...) |
| `area:cdss` | Risk bands, alerts, clinical recommendations |
| `area:scribe` | AI Scribe, voice, realtime transcription |
| `area:coaching` | Visit briefing, coaching cards |
| `area:teleconsult` | Teleconsult |
| `area:household` | Households, members, enrollment, search |
| `area:push` | Notifications |
| `area:i18n` | Bangla/English text, translations |
| `area:release` | Builds, versions, Play Store |
| `area:ci` | CI, tooling, developer workflow |

### 6. Preview and confirm
Show the complete issue exactly as it will be filed:

```
Title:  [Bug] <short, specific summary>
Labels: bug, area:sync, env:training
Body:
<full Markdown body from the reference template>
```

Then ask: "Shall I create this issue? (yes / change something)". Create it **only** after an explicit yes. Any edit -> re-scrub and show the preview again.

Title rules: start with the form prefix (`[Bug] `, `[Feature] `, `[Task] `, `[Release] `), 80 characters or fewer, say what is wrong or wanted and where ("[Bug] Sync stuck at 90% after adding a household member").

### 7. Create
**Claude Code:**
1. Write the body to a temporary file (e.g. a path from `mktemp`), never inline it into the shell command. Write it with the Write tool (preferred) or a quoted heredoc (`<<'EOF'`) - never an unquoted heredoc or `echo` of user text.
2. `gh issue create --repo Medtronic-LABS/uhis_lf_mobile --title '<title>' --body-file <tmpfile> --label <type> --label <area:...> [--label <env:...>]`
   (quote the title in single quotes; escape any single quote in it as `'\''`).
3. If `gh` fails because a label does not exist yet, retry with only the type label and tell the user which label to add later.
4. `gh project item-add 4 --owner Medtronic-LABS --url <issue-url>` - adds it to the LeapWell project for triage. If this fails (missing `project` scope), give the user the issue link and say a maintainer will add it to the project.
5. Delete the temporary file.

**Chat:** call the connector's create-issue tool (`issue_write`, method `create`) with owner `Medtronic-LABS`, repo `uhis_lf_mobile`, the title, body and labels. Adding to Project #4 happens at triage; say so.
If the labels did not stick (the reporter lacks triage rights), that is fine: the title prefix identifies the type and triage adds the labels.

### 8. Report
Reply with the issue link, the labels applied, the suggested priority (as a suggestion), and what was scrubbed. Remind them to add screenshots on GitHub if useful (test data only).

## No-tool fallback (chat without a GitHub connector)
1. Show the final scrubbed title and body as Markdown in one copyable block.
2. Give a prefilled link built from the reference file's field ids, URL-encoding every value:
   `https://github.com/Medtronic-LABS/uhis_lf_mobile/issues/new?template=<type>.yml&title=<urlencoded title>&<field-id>=<urlencoded value>...`
   (`<type>` is `bug`, `feature`, `task` or `release`). If the link would be longer than about 6000 characters, leave the long text fields out of it and tell the user to paste those sections from the block.
3. Tell the user to open the link, check each field, tick the Privacy check box, add the area/env labels if they can (otherwise triage will), and submit.

## Never
- Never create, edit or comment without an explicit "yes" to the exact preview.
- Never file a security vulnerability publicly.
- Never put real names, phone numbers, IDs, locations, credentials or raw logs in an issue.
- Never set or claim a priority, assignee, milestone or project field - humans do that at triage.
