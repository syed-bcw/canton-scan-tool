#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../_lib/http.sh"

# POST /v0/holdings/state
#
# This endpoint returns paginated created-events for holdings-related templates.
#
# Env:
#   PARTY_ID=...                        (optional; used if OWNER_PARTY_IDS not set)
#   OWNER_PARTY_IDS='p1,p2,...'         (optional; overrides PARTY_ID)
#   PAGE_SIZE=100                       (optional)
#   AFTER=123                           (optional next_page_token)
#   MIGRATION_ID=1                      (optional; auto-detected if unset)
#   RECORD_TIME='2026-01-22T...'        (optional; auto-detected if unset)
#   RECORD_TIME_MATCH=exact             (optional; default exact)
#   BEFORE='2026-01-25T00:00:00Z'       (optional; used only for RECORD_TIME auto-detect)
#   PAYLOAD='{"migration_id":1,...}'  (optional; overrides generated payload)

PAGE_SIZE="${PAGE_SIZE:-100}"

if [ -n "${PAYLOAD:-}" ]; then
  payload="$PAYLOAD"
else
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required unless you set PAYLOAD=..." >&2
    exit 3
  fi

  if ! echo "$PAGE_SIZE" | grep -qE '^[0-9]+$'; then
    echo "PAGE_SIZE must be an integer" >&2
    exit 2
  fi
  if [ -n "${AFTER:-}" ] && ! echo "${AFTER}" | grep -qE '^[0-9]+$'; then
    echo "AFTER must be an integer" >&2
    exit 2
  fi

  RECORD_TIME_MATCH="${RECORD_TIME_MATCH:-exact}"
  MIGRATION_ID="${MIGRATION_ID:-}"
  RECORD_TIME="${RECORD_TIME:-}"

  owner_csv="${OWNER_PARTY_IDS:-}"
  if [ -z "$owner_csv" ] && [ -n "${PARTY_ID:-}" ]; then
    owner_csv="$PARTY_ID"
  fi
  if [ -z "$owner_csv" ]; then
    echo "Set PARTY_ID=... or OWNER_PARTY_IDS='p1,p2,...' (or set PAYLOAD)" >&2
    exit 2
  fi

  if [ -z "$MIGRATION_ID" ]; then
    MIGRATION_ID=$(scan_get "/v0/dso-sequencers" | jq -r '.domainSequencers[0].sequencers[0].migrationId // empty' 2>/dev/null || true)
  fi
  if [ -z "$MIGRATION_ID" ]; then
    MIGRATION_ID=$(scan_post_json "/v2/updates" '{"page_size":1,"daml_value_encoding":"compact_json"}' | jq -r '.transactions[0].migration_id // empty' 2>/dev/null || true)
  fi
  if [ -z "$MIGRATION_ID" ]; then
    echo "Could not determine MIGRATION_ID automatically; set MIGRATION_ID=..." >&2
    exit 4
  fi

  if [ -z "$RECORD_TIME" ]; then
    before="${BEFORE:-}"
    if [ -z "$before" ]; then
      before=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    fi
    before_enc=$(jq -rn --arg v "$before" '$v|@uri')
    RECORD_TIME=$(scan_get "/v0/state/acs/snapshot-timestamp?before=${before_enc}&migration_id=${MIGRATION_ID}" | jq -r '.record_time // empty' 2>/dev/null || true)
  fi
  if [ -z "$RECORD_TIME" ]; then
    echo "Could not determine RECORD_TIME automatically; set RECORD_TIME=..." >&2
    exit 4
  fi

  payload=$(jq -cn \
    --arg record_time "$RECORD_TIME" \
    --arg record_time_match "$RECORD_TIME_MATCH" \
    --arg owner_csv "$owner_csv" \
    --argjson migration_id "$MIGRATION_ID" \
    --argjson page_size "$PAGE_SIZE" \
    --arg after "${AFTER:-}" \
    '
    def csv_to_array($s):
      ($s
        | split(",")
        | map(gsub("^\\s+|\\s+$"; ""))
        | map(select(length > 0)));

    {
      migration_id: $migration_id,
      record_time: $record_time,
      record_time_match: $record_time_match,
      page_size: $page_size,
      owner_party_ids: csv_to_array($owner_csv)
    }
    + (if ($after|length) > 0 then {after: ($after|tonumber)} else {} end)
    '
  )
fi

scan_post_json "/v0/holdings/state" "$payload"
