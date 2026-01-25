#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../_lib/http.sh"

# POST /v0/holdings/summary
#
# This endpoint provides an aggregate, balance-like view for one or more parties.
#
# Env:
#   PARTY_ID=...                     (optional; used if OWNER_PARTY_IDS not set)
#   OWNER_PARTY_IDS='p1,p2,...'      (optional; overrides PARTY_ID)
#   AS_OF_ROUND=123                  (optional)
#   MIGRATION_ID=1                   (optional; auto-detected if unset)
#   RECORD_TIME='2026-01-22T...'     (optional; auto-detected if unset)
#   RECORD_TIME_MATCH=exact          (optional; default exact)
#   BEFORE='2026-01-25T00:00:00Z'    (optional; used only for RECORD_TIME auto-detect)
#   PAYLOAD='{"migration_id":1,...}' (optional; overrides generated payload)

if [ -n "${PAYLOAD:-}" ]; then
  payload="$PAYLOAD"
else
  if ! command -v jq >/dev/null 2>&1; then
    echo "jq is required unless you set PAYLOAD=..." >&2
    exit 3
  fi

  RECORD_TIME_MATCH="${RECORD_TIME_MATCH:-exact}"
  MIGRATION_ID="${MIGRATION_ID:-}"
  RECORD_TIME="${RECORD_TIME:-}"

  # Determine owner parties
  owner_csv="${OWNER_PARTY_IDS:-}"
  if [ -z "$owner_csv" ] && [ -n "${PARTY_ID:-}" ]; then
    owner_csv="$PARTY_ID"
  fi

  if [ -z "$owner_csv" ]; then
    echo "Set PARTY_ID=... or OWNER_PARTY_IDS='p1,p2,...' (or set PAYLOAD)" >&2
    exit 2
  fi

  # Auto-detect MIGRATION_ID
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

  # Auto-detect RECORD_TIME using ACS snapshot timestamp
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
    --arg as_of_round "${AS_OF_ROUND:-}" \
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
      owner_party_ids: csv_to_array($owner_csv)
    }
    + (if ($as_of_round|length) > 0 then {as_of_round: ($as_of_round|tonumber)} else {} end)
    '
  )
fi

scan_post_json "/v0/holdings/summary" "$payload"
