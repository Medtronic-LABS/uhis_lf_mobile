#!/usr/bin/env bash
# Configure GitHub Project #4 fields (Priority, Status, Sprint). Dry-run by default.
set -euo pipefail
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

usage() {
  cat <<USAGE
Usage: scripts/github/setup_project.sh [--apply [--i-understand-status-reset]] [--help]

Configures project #$PROJECT of $OWNER:
  Priority  options P0, P1, P2, P3
  Status    options Triage, Backlog, Ready, In progress, In review, QA, Done
  Sprint    iteration field, 2-week cadence
Default is a dry-run that only prints the GraphQL calls.

The Status step REPLACES the option list (updateProjectV2Field). Existing option
ids may change and items can lose their Status value, so --apply refuses to run
unless --i-understand-status-reset is also given. Export/back up the project first.
USAGE
}

parse_common_flags usage "$@"
banner

ACK_RESET=0
for arg in "${REST[@]+"${REST[@]}"}"; do
  case "$arg" in
    --i-understand-status-reset) ACK_RESET=1 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

if [ "$APPLY" -eq 1 ] && [ "$ACK_RESET" -eq 0 ]; then
  echo "error: --apply also requires --i-understand-status-reset (Status options are replaced; see --help)." >&2
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
echo "WARNING: Status step replaces the whole option list."
echo "  Existing options are kept by name unchanged: Backlog, Ready, In progress, In review, Done."
echo "  Only Triage (first) and QA (between In review and Done) are added."
echo "  Option ids may change, so item Status values can reset. Export/back up the project"
echo "  (and note current item statuses) before running with --apply."
echo "-- Status --"
graphql "$(options_body "$(field_id Status)" \
  "Triage:PURPLE" "Backlog:GRAY" "Ready:BLUE" "In progress:YELLOW" \
  "In review:ORANGE" "QA:PINK" "Done:GREEN")"

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
