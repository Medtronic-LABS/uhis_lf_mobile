# Jira retirement for LEAPWELL

**Decision (2026-11-04):** the Jira project LEAP is retired for the LEAPWELL app
(`uhis_lf_mobile`). GitHub Issues plus the org Project "LeapWell" (#4) is the only tracker.
Branches, commits and PRs reference GitHub issues as `#N`; Jira keys are not used in new work.

**Freeze date:** `<set by owner>` — after this date no new tickets are created in Jira LEAP.

## Moving open Jira tickets

For each open Jira ticket that is still wanted:

1. File it again on GitHub with `/lw-ticket` (or "file a bug" in Claude chat), answering the
   questions from the Jira ticket. Apply the privacy rule: the GitHub repo is public, so copy no
   patient data, credentials or raw logs from Jira.
2. Put the old key once at the end of the issue body, e.g. `Migrated from LEAP-123`.
   This file is the only place in the repo docs where Jira keys appear.
3. Close the Jira ticket with a comment linking the new GitHub issue.

Tickets no longer needed are closed in Jira with a short reason, not migrated. Nothing is migrated
automatically. Closed Jira tickets stay in Jira as history.
