#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required (used for input extraction + JSON validation)" >&2
  exit 3
fi

# Treat non-2xx HTTP responses as failures (keeps response body for analysis).
# Can be overridden by setting API_CURL_EXTRA explicitly.
if [[ "${API_CURL_EXTRA:-}" != *"--fail-with-body"* ]]; then
  export API_CURL_EXTRA="${API_CURL_EXTRA:-} --fail-with-body"
fi

OUT_BASE="${OUT_BASE:-out}"
RUN_ID="$(date -u +%Y%m%dT%H%M%SZ)"
OUT_DIR="${OUT_BASE}/run-${RUN_ID}"
mkdir -p "$OUT_DIR"

log() {
  printf "[%s] %s\n" "$(date -u +%H:%M:%SZ)" "$*" >&2
}

cmd_to_string() {
  local -a parts=()
  local x
  for x in "$@"; do
    parts+=("$(printf '%q' "$x")")
  done
  printf "%s" "${parts[*]}"
}

run_and_capture() {
  local name="$1"; shift
  local stdout_file="$OUT_DIR/${name}.out"
  local stderr_file="$OUT_DIR/${name}.stderr"
  local meta_file="$OUT_DIR/${name}.meta.json"

  local cmd_str
  cmd_str="$(cmd_to_string "$@")"

  log "RUN  ${name}"

  set +e
  "$@" >"$stdout_file" 2>"$stderr_file"
  local exit_code=$?
  set -e

  local valid_json=false
  if jq -e . <"$stdout_file" >/dev/null 2>&1; then
    valid_json=true
  fi

  jq -cn \
    --arg name "$name" \
    --arg cmd "$cmd_str" \
    --argjson exit_code "$exit_code" \
    --argjson valid_json "$valid_json" \
    --arg stdout_file "${name}.out" \
    --arg stderr_file "${name}.stderr" \
    '{name:$name, cmd:$cmd, exit_code:$exit_code, valid_json:$valid_json, stdout:$stdout_file, stderr:$stderr_file}' \
    >"$meta_file"
}

run_and_capture_retry() {
  local name="$1"; shift
  local max_tries="${API_TRIES:-3}"
  local try=1

  while true; do
    run_and_capture "$name" "$@"

    local meta_file="$OUT_DIR/${name}.meta.json"
    local exit_code
    exit_code="$(jq -r '.exit_code' "$meta_file")"
    if [[ "$exit_code" == "0" ]]; then
      return 0
    fi

    # Retry common transient curl TLS/protocol issues.
    if [[ "$exit_code" == "35" || "$exit_code" == "56" ]]; then
      if [[ "$try" -lt "$max_tries" ]]; then
        log "RETRY ${name} (exit=${exit_code}) try=${try}/${max_tries}"
        sleep "${API_RETRY_SLEEP_SECS:-1}"
        try=$((try + 1))
        continue
      fi
    fi

    return 0
  done
}

# --------
# Discovery (derive inputs from Scan)
# --------

log "Output directory: ${OUT_DIR}"

# 1) Fetch validator licenses (also used to derive party IDs)
run_and_capture_retry "scan.v0.admin_validator_licenses" ./run_api.sh run scan.v0.admin_validator_licenses

LICENSES_JSON="$OUT_DIR/scan.v0.admin_validator_licenses.out"

PRIMARY_PARTY_ID="$(jq -r '.validator_licenses[0].payload.validator // empty' "$LICENSES_JSON")"
VALIDATOR_IDS_CSV="$(jq -r '[.validator_licenses[].payload.validator] | map(select(. != null and . != "")) | unique | .[0:10] | join(",")' "$LICENSES_JSON")"

# 2) Domain ID (used for participant-id + traffic-status)
DOMAIN_ID=""
run_and_capture_retry "scan.v0.scans" ./run_api.sh run scan.v0.scans
SCANS_JSON="$OUT_DIR/scan.v0.scans.out"
DOMAIN_ID="$(jq -r '.scans[0].domainId // empty' "$SCANS_JSON")"

# 3) Migration ID + record time (used for ACS + holdings)
MIGRATION_ID=""
RECORD_TIME=""
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

run_and_capture_retry "scan.v0.dso_sequencers" ./run_api.sh run scan.v0.dso_sequencers
DSO_SEQ_JSON="$OUT_DIR/scan.v0.dso_sequencers.out"
MIGRATION_ID="$(jq -r '.domainSequencers[0].sequencers[0].migrationId // empty' "$DSO_SEQ_JSON" 2>/dev/null || true)"

if [[ -z "$MIGRATION_ID" ]]; then
  log "Could not parse migrationId from /v0/dso-sequencers; falling back to /v2/updates"
  run_and_capture_retry "scan.v2.updates.discovery" env PAGE_SIZE=1 DAML_VALUE_ENCODING=compact_json ./run_api.sh run scan.v2.updates
  UPDATES_DISC_JSON="$OUT_DIR/scan.v2.updates.discovery.out"
  MIGRATION_ID="$(jq -r '.transactions[0].migration_id // empty' "$UPDATES_DISC_JSON" 2>/dev/null || true)"
fi

if [[ -n "$MIGRATION_ID" ]]; then
  run_and_capture_retry "scan.v0.state_acs_snapshot_timestamp" ./run_api.sh run scan.v0.state_acs_snapshot_timestamp -- "$NOW_ISO" "$MIGRATION_ID"
  SNAP_JSON="$OUT_DIR/scan.v0.state_acs_snapshot_timestamp.out"
  RECORD_TIME="$(jq -r '.record_time // empty' "$SNAP_JSON" 2>/dev/null || true)"
fi

# 4) Update ID (used for /v2/updates/{update_id} and /v0/events/{update_id})
UPDATE_ID=""
if [[ -f "${OUT_DIR}/scan.v2.updates.discovery.out" ]]; then
  UPDATE_ID="$(jq -r '.transactions[0].update_id // empty' "$OUT_DIR/scan.v2.updates.discovery.out" 2>/dev/null || true)"
else
  run_and_capture_retry "scan.v2.updates.discovery" env PAGE_SIZE=1 DAML_VALUE_ENCODING=compact_json ./run_api.sh run scan.v2.updates
  UPDATES_DISC_JSON="$OUT_DIR/scan.v2.updates.discovery.out"
  UPDATE_ID="$(jq -r '.transactions[0].update_id // empty' "$UPDATES_DISC_JSON" 2>/dev/null || true)"
fi

# 5) ANS name (best-effort for by-name)
ANS_NAME=""
ANS_USER_PARTY=""
run_and_capture_retry "scan.v0.ans_entries.discovery" ./run_api.sh run scan.v0.ans_entries -- 20
ANS_DISC_JSON="$OUT_DIR/scan.v0.ans_entries.discovery.out"
ANS_NAME="$(jq -r '.entries[0].name // empty' "$ANS_DISC_JSON" 2>/dev/null || true)"
ANS_USER_PARTY="$(jq -r '.entries[0].user // empty' "$ANS_DISC_JSON" 2>/dev/null || true)"
if [[ -z "$ANS_NAME" ]]; then
  ANS_NAME="alice"
fi

# 6) Participant/member ID (best-effort)
MEMBER_ID=""
if [[ -n "$DOMAIN_ID" && -n "$PRIMARY_PARTY_ID" ]]; then
  run_and_capture "scan.v0.domains_party_participant_id.discovery" ./run_api.sh run scan.v0.domains_party_participant_id -- "$DOMAIN_ID" "$PRIMARY_PARTY_ID"
  PARTY_PARTIC_JSON="$OUT_DIR/scan.v0.domains_party_participant_id.discovery.out"
  MEMBER_ID="$(jq -r '.participant_id // empty' "$PARTY_PARTIC_JSON" 2>/dev/null || true)"
fi

jq -cn \
  --arg run_id "$RUN_ID" \
  --arg out_dir "$OUT_DIR" \
  --arg primary_party_id "$PRIMARY_PARTY_ID" \
  --arg validator_ids_csv "$VALIDATOR_IDS_CSV" \
  --arg domain_id "$DOMAIN_ID" \
  --arg member_id "$MEMBER_ID" \
  --arg migration_id "$MIGRATION_ID" \
  --arg record_time "$RECORD_TIME" \
  --arg update_id "$UPDATE_ID" \
  --arg ans_name "$ANS_NAME" \
  --arg ans_user_party "$ANS_USER_PARTY" \
  '{run_id:$run_id,out_dir:$out_dir,primary_party_id:$primary_party_id,validator_ids_csv:$validator_ids_csv,domain_id:$domain_id,member_id:$member_id,migration_id:$migration_id,record_time:$record_time,update_id:$update_id,ans_name:$ans_name,ans_user_party:$ans_user_party}' \
  >"$OUT_DIR/_discovery.json"

log "Discovery: PARTY_ID=${PRIMARY_PARTY_ID:-<none>} DOMAIN_ID=${DOMAIN_ID:-<none>} MEMBER_ID=${MEMBER_ID:-<none>} MIGRATION_ID=${MIGRATION_ID:-<none>} RECORD_TIME=${RECORD_TIME:-<none>} UPDATE_ID=${UPDATE_ID:-<none>}"

# --------
# Run all APIs (comprehensive)
# --------

# Common (no inputs)
run_and_capture_retry "scan.common.livez" ./run_api.sh run scan.common.livez
run_and_capture_retry "scan.common.readyz" ./run_api.sh run scan.common.readyz
run_and_capture_retry "scan.common.status" ./run_api.sh run scan.common.status
run_and_capture_retry "scan.common.version" ./run_api.sh run scan.common.version

# v0 - discovery / static
run_and_capture_retry "scan.v0.dso" ./run_api.sh run scan.v0.dso
run_and_capture_retry "scan.v0.dso_party_id" ./run_api.sh run scan.v0.dso_party_id
# already ran dso_sequencers, scans, admin_validator_licenses

run_and_capture_retry "scan.v0.closed_rounds" ./run_api.sh run scan.v0.closed_rounds
run_and_capture_retry "scan.v0.open_and_issuing_mining_rounds" ./run_api.sh run scan.v0.open_and_issuing_mining_rounds

# v0 - ANS
run_and_capture_retry "scan.v0.ans_entries" ./run_api.sh run scan.v0.ans_entries -- 50
run_and_capture_retry "scan.v0.ans_entries_by_name" ./run_api.sh run scan.v0.ans_entries_by_name -- "$ANS_NAME"
if [[ -n "$ANS_USER_PARTY" ]]; then
  run_and_capture_retry "scan.v0.ans_entries_by_party" ./run_api.sh run scan.v0.ans_entries_by_party -- "$ANS_USER_PARTY"
else
  log "SKIP scan.v0.ans_entries_by_party (no ANS user party discovered)"
fi

# v0 - holdings
if [[ -n "$PRIMARY_PARTY_ID" ]]; then
  if [[ -n "$MIGRATION_ID" && -n "$RECORD_TIME" ]]; then
    run_and_capture_retry "scan.v0.holdings_summary" env PARTY_ID="$PRIMARY_PARTY_ID" MIGRATION_ID="$MIGRATION_ID" RECORD_TIME="$RECORD_TIME" ./run_api.sh run scan.v0.holdings_summary
    run_and_capture_retry "scan.v0.holdings_state" env PARTY_ID="$PRIMARY_PARTY_ID" MIGRATION_ID="$MIGRATION_ID" RECORD_TIME="$RECORD_TIME" PAGE_SIZE=25 ./run_api.sh run scan.v0.holdings_state
  else
    run_and_capture_retry "scan.v0.holdings_summary" env PARTY_ID="$PRIMARY_PARTY_ID" ./run_api.sh run scan.v0.holdings_summary
    run_and_capture_retry "scan.v0.holdings_state" env PARTY_ID="$PRIMARY_PARTY_ID" PAGE_SIZE=25 ./run_api.sh run scan.v0.holdings_state
  fi
else
  log "SKIP holdings_* (no PRIMARY_PARTY_ID discovered)"
fi

# v0 - domains / traffic
if [[ -n "$DOMAIN_ID" && -n "$PRIMARY_PARTY_ID" ]]; then
  run_and_capture_retry "scan.v0.domains_party_participant_id" ./run_api.sh run scan.v0.domains_party_participant_id -- "$DOMAIN_ID" "$PRIMARY_PARTY_ID"
else
  log "SKIP domains_party_participant_id (missing DOMAIN_ID or PRIMARY_PARTY_ID)"
fi

if [[ -n "$DOMAIN_ID" && -n "$MEMBER_ID" ]]; then
  run_and_capture_retry "scan.v0.domains_member_traffic_status" env DOMAIN_ID="$DOMAIN_ID" MEMBER_ID="$MEMBER_ID" ./run_api.sh run scan.v0.domains_member_traffic_status
else
  log "SKIP domains_member_traffic_status (missing DOMAIN_ID or MEMBER_ID)"
fi

# v0 - validator faucets
if [[ -n "$VALIDATOR_IDS_CSV" ]]; then
  run_and_capture_retry "scan.v0.validators_validator_faucets" env VALIDATOR_IDS="$VALIDATOR_IDS_CSV" ./run_api.sh run scan.v0.validators_validator_faucets
else
  log "SKIP validators_validator_faucets (no VALIDATOR_IDS discovered)"
fi

# v0 - events
run_and_capture_retry "scan.v0.events" env PAGE_SIZE=25 DAML_VALUE_ENCODING=compact_json ./run_api.sh run scan.v0.events
if [[ -n "$UPDATE_ID" ]]; then
  run_and_capture_retry "scan.v0.events_by_update_id" ./run_api.sh run scan.v0.events_by_update_id -- "$UPDATE_ID"
else
  log "SKIP events_by_update_id (no UPDATE_ID discovered)"
fi

# v0 - ACS
if [[ -n "$MIGRATION_ID" && -n "$RECORD_TIME" ]]; then
  # Already ran snapshot timestamp.
  run_and_capture_retry "scan.v0.state_acs_snapshot_timestamp_after" ./run_api.sh run scan.v0.state_acs_snapshot_timestamp_after -- "$RECORD_TIME" "$MIGRATION_ID"
  run_and_capture_retry "scan.v0.state_acs" env MIGRATION_ID="$MIGRATION_ID" RECORD_TIME="$RECORD_TIME" PAGE_SIZE=50 PARTY_IDS="${PRIMARY_PARTY_ID:-}" ./run_api.sh run scan.v0.state_acs
else
  log "SKIP state_acs* (missing MIGRATION_ID or RECORD_TIME)"
fi

# v2 - updates
run_and_capture_retry "scan.v2.updates" env PAGE_SIZE=25 DAML_VALUE_ENCODING=compact_json ./run_api.sh run scan.v2.updates
if [[ -n "$UPDATE_ID" ]]; then
  run_and_capture_retry "scan.v2.updates_tx" ./run_api.sh run scan.v2.updates_tx -- "$UPDATE_ID"
else
  log "SKIP v2.updates_tx (no UPDATE_ID discovered)"
fi

# Flows (not APIs; still useful outputs)
if [[ "${RUN_FLOWS:-1}" == "1" ]]; then
  run_and_capture_retry "flows.scan_scans_first_url" ./run_api.sh run flows.scan_scans_first_url
  run_and_capture_retry "flows.validator_licenses_summary" ./run_api.sh run flows.validator_licenses_summary -- "$LICENSES_JSON"
  run_and_capture_retry "flows.validator_licenses_extract_validators" ./run_api.sh run flows.validator_licenses_extract_validators -- "$LICENSES_JSON"

  # This flow can be slow; default to a small sample unless overridden.
  limit_validators="${LIMIT_VALIDATORS:-10}"
  run_and_capture_retry "flows.scan_participant_ids_for_validators" env LIMIT_VALIDATORS="$limit_validators" ./run_api.sh run flows.scan_participant_ids_for_validators -- "$LICENSES_JSON"
else
  log "SKIP flows.* (set RUN_FLOWS=1 to include)"
fi

# --------
# Index + report
# --------

jq -cs '.' "$OUT_DIR"/*.meta.json >"$OUT_DIR/_index.json"

TOTAL="$(jq 'length' "$OUT_DIR/_index.json")"
FAILS="$(jq '[.[] | select(.exit_code != 0)] | length' "$OUT_DIR/_index.json")"
INVALID="$(jq '[.[] | select((.exit_code == 0) and (.valid_json == false) and (.name | startswith("flows." ) | not))] | length' "$OUT_DIR/_index.json")"

jq -cn \
  --arg run_id "$RUN_ID" \
  --arg out_dir "$OUT_DIR" \
  --argjson total "$TOTAL" \
  --argjson failed "$FAILS" \
  --argjson non_json_api "$INVALID" \
  --arg curl_extra "${API_CURL_EXTRA:-}" \
  '{run_id:$run_id,out_dir:$out_dir,total:$total,failed:$failed,non_json_api_outputs:$non_json_api,curl_extra:$curl_extra}' \
  >"$OUT_DIR/_report.json"

log "Done. total=${TOTAL} failed=${FAILS} invalid_json(api_only)=${INVALID}"
log "Index: ${OUT_DIR}/_index.json"
log "Report: ${OUT_DIR}/_report.json"
