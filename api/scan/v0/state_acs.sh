#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../_lib/http.sh"

# POST /v0/state/acs
# Required env:
#   MIGRATION_ID=... (integer)
#   RECORD_TIME=... (timestamp string)
# Optional env:
#   RECORD_TIME_MATCH=exact (exact|before|after)
#   AFTER=... (integer next_page_token)
#   PAGE_SIZE=100
#   PARTY_IDS="p1,p2,..." (CSV)
#   TEMPLATES="pkg:Module:Template,pkg:Other:Tpl" (CSV)

MIGRATION_ID="${MIGRATION_ID:-}"
RECORD_TIME="${RECORD_TIME:-}"
RECORD_TIME_MATCH="${RECORD_TIME_MATCH:-exact}"
AFTER="${AFTER:-}"
PAGE_SIZE="${PAGE_SIZE:-100}"
PARTY_IDS="${PARTY_IDS:-}"
TEMPLATES="${TEMPLATES:-}"

if [ -z "$MIGRATION_ID" ] || [ -z "$RECORD_TIME" ]; then
  echo "Required: MIGRATION_ID=... RECORD_TIME=..." >&2
  exit 2
fi

if ! echo "$MIGRATION_ID" | grep -qE '^[0-9]+$'; then
  echo "MIGRATION_ID must be an integer" >&2
  exit 2
fi

if ! echo "$PAGE_SIZE" | grep -qE '^[0-9]+$'; then
  echo "PAGE_SIZE must be an integer" >&2
  exit 2
fi

if [ -n "$AFTER" ] && ! echo "$AFTER" | grep -qE '^[0-9]+$'; then
  echo "AFTER must be an integer" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to build JSON payload" >&2
  exit 3
fi

payload=$(jq -cn \
  --arg record_time "$RECORD_TIME" \
  --arg record_time_match "$RECORD_TIME_MATCH" \
  --argjson migration_id "$MIGRATION_ID" \
  --argjson page_size "$PAGE_SIZE" \
  --arg after "$AFTER" \
  --arg party_ids_csv "$PARTY_IDS" \
  --arg templates_csv "$TEMPLATES" \
  '
  def csv_to_array($s):
    if ($s|length) == 0 then
      []
    else
      ($s
        | split(",")
        | map(gsub("^\\s+|\\s+$"; ""))
        | map(select(length > 0)))
    end;

  {
    migration_id: $migration_id,
    record_time: $record_time,
    record_time_match: $record_time_match,
    page_size: $page_size
  }
  + (if ($after|length) > 0 then {after: ($after|tonumber)} else {} end)
  + (if ($party_ids_csv|length) > 0 then {party_ids: csv_to_array($party_ids_csv)} else {} end)
  + (if ($templates_csv|length) > 0 then {templates: csv_to_array($templates_csv)} else {} end)
  '
)

scan_post_json "/v0/state/acs" "$payload"
