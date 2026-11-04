#!/usr/bin/env bash
# Configure GitHub Project #4 fields (Priority, Status, Sprint). Dry-run by default.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  cat <<USAGE
Usage: scripts/github/setup_project.sh [--apply] [--help]

Configures project #$PROJECT of $OWNER:
  Priority  options P0, P1, P2, P3 (API)
  Sprint    iteration field, 2-week cadence (API)
  Status    NOT touched by this script: replacing the option list via the API can
            wipe item values. Add Triage and QA in the UI (steps printed).
Default is a dry-run that only prints the GraphQL calls.
USAGE
}

parse_common_flags usage "$@"
banner

if [ "${#REST[@]}" -gt 0 ]; then
  echo "unknown argument: ${REST[0]}" >&2
  exit 2
fi

# Read-only lookups; placeholders in dry-run so no network/gh call is made.
project_id() {
  if [ "$APPLY" -eq 1 ]; then
    gh project view "$PROJECT" --owner "$OWNER" --format json --jq .id
  else
    echo "<PROJECT_NODE_ID>"
  fi
}

field_id() {
  local name="$1"
  if [ "$APPLY" -eq 1 ]; then
    gh project field-list "$PROJECT" --owner "$OWNER" --format json \
      --jq ".fields[] | select(.name==\"$name\") | .id"
  else
    echo "<$(echo "$name" | tr '[:lower:]' '[:upper:]')_FIELD_NODE_ID>"
  fi
}

# Build a singleSelectOptions mutation body from "Name:COLOR" pairs.
options_body() {
  local fid="$1"
  shift
  python3 - "$fid" "$@" <<'PY'
import json, sys
fid, pairs = sys.argv[1], sys.argv[2:]
opts = []
for p in pairs:
    name, color = p.rsplit(":", 1)
    opts.append({"name": name, "color": color, "description": ""})
query = (
    "mutation($fieldId: ID!, $opts: [ProjectV2SingleSelectFieldOptionInput!]!) {"
    " updateProjectV2Field(input: {fieldId: $fieldId, singleSelectOptions: $opts})"
    " { projectV2Field { ... on ProjectV2SingleSelectField { id options { id name } } } } }"
)
print(json.dumps({"query": query, "variables": {"fieldId": fid, "opts": opts}}, indent=2))
PY
}

graphql() {
  run_stdin "$1" gh api graphql --input -
}

echo
echo "-- Priority (no existing items carry a value; safe) --"
graphql "$(options_body "$(field_id Priority)" \
  "P0:RED" "P1:ORANGE" "P2:YELLOW" "P3:GRAY")"

echo
echo "-- Status (UI only; this script never edits Status) --"
echo "  The API replaces the whole option list and can wipe item Status values."
echo "  In the UI: Project -> Settings -> Status field ->"
echo "    add 'Triage' and drag it to the top;"
echo "    add 'QA' and place it between 'In review' and 'Done'."
echo "  Adding options in the UI keeps existing item values."
echo "  Target order: Triage, Backlog, Ready, In progress, In review, QA, Done."

echo
echo "-- Sprint (iteration, 2 weeks) --"
START_DATE="$(python3 -c 'import datetime as d; t=d.date.today(); print(t + d.timedelta(days=(7 - t.weekday()) % 7 or 7))')"
SPRINT_BODY="$(python3 - "$(project_id)" "$START_DATE" <<'PY'
import json, sys
pid, start = sys.argv[1:3]
query = (
    "mutation($projectId: ID!, $start: Date!) {"
    " createProjectV2Field(input: {projectId: $projectId, dataType: ITERATION, name: \"Sprint\","
    " iterationConfiguration: {startDate: $start, duration: 14, iterations: []}})"
    " { projectV2Field { ... on ProjectV2IterationField { id name } } } }"
)
print(json.dumps({"query": query, "variables": {"projectId": pid, "start": start}}, indent=2))
PY
)"
graphql "$SPRINT_BODY"
echo "NOTE: the iteration input shape is unverified. If it errors, create it in the UI instead:"
echo "  Project -> Settings -> New field -> name 'Sprint' -> type Iteration -> duration 2 weeks."

echo
echo "-- Built-in workflows to enable manually (UI only: Project -> Workflows) --"
echo "  * Item added to project   -> set Status = Triage"
echo "  * Item closed             -> set Status = Done"
echo "  * Pull request merged     -> set Status = Done"
echo "  * Auto-add to project     -> filter: is:issue,pr repo:$OWNER/$REPO"
