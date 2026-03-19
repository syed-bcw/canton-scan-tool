#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DATA_DIR="${DATA_DIR:-$ROOT_DIR/data}"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"

SV_DIR="$DATA_DIR/run-$RUN_ID/sv"
VALIDATOR_DIR="$DATA_DIR/run-$RUN_ID/validator"
AUTH_DIR="$DATA_DIR/run-$RUN_ID/auth"

mkdir -p "$SV_DIR" "$VALIDATOR_DIR" "$AUTH_DIR"

echo "run_id=$RUN_ID" > "$DATA_DIR/run-$RUN_ID/meta.txt"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd jq
require_cmd curl

VALIDATOR_NAME="${VALIDATOR_NAME:-arkhia}"

# --------
# Scan API (Super Validator) dependencies
# --------

SV_ENV=(
  "SCAN_SCHEME=${SCAN_SCHEME:-https}"
  "SCAN_HOST=${SCAN_HOST:-scan.sv-1.global.canton.network.sync.global}"
  "SCAN_PORT=${SCAN_PORT:-3128}"
  "SCAN_IP=${SCAN_IP:-127.0.0.1}"
  "SCAN_PREFIX=${SCAN_PREFIX:-/api/scan}"
)

run_to_file() {
  local out_file="$1"
  shift
  # shellcheck disable=SC2068
  "$@" > "$out_file"
}

json_get() {
  # Usage: json_get file jq_filter
  local file="$1"
  local filter="$2"
  jq -r "$filter" < "$file"
}

domain_json="$SV_DIR/scan.v0.scans.json"
echo "Discovering domain_id via /v0/scans..." >&2
SCAN_SCHEME="${SV_ENV[0]#*=}" \
SCAN_HOST="${SV_ENV[1]#*=}" \
SCAN_PORT="${SV_ENV[2]#*=}" \
SCAN_IP="${SV_ENV[3]#*=}" \
SCAN_PREFIX="${SV_ENV[4]#*=}" \
  ./run_api.sh run scan.v0.scans >/dev/null 2>"$SV_DIR/scan.v0.scans.err" || true
# run_api.sh captures stdout itself; we re-run with redirection for correct output file
SCAN_SCHEME="${SV_ENV[0]#*=}" \
SCAN_HOST="${SV_ENV[1]#*=}" \
SCAN_PORT="${SV_ENV[2]#*=}" \
SCAN_IP="${SV_ENV[3]#*=}" \
SCAN_PREFIX="${SV_ENV[4]#*=}" \
  ./run_api.sh run scan.v0.scans > "$domain_json"

DOMAIN_ID="$(json_get "$domain_json" '.scans[0].domainId // empty')"
if [ -z "$DOMAIN_ID" ]; then
  echo "Could not derive DOMAIN_ID from scan.v0.scans response" >&2
  exit 2
fi

dso_json="$SV_DIR/scan.v0.dso_sequencers.json"
echo "Discovering migration_id via /v0/dso-sequencers..." >&2
SCAN_SCHEME="${SV_ENV[0]#*=}" \
SCAN_HOST="${SV_ENV[1]#*=}" \
SCAN_PORT="${SV_ENV[2]#*=}" \
SCAN_IP="${SV_ENV[3]#*=}" \
SCAN_PREFIX="${SV_ENV[4]#*=}" \
  ./run_api.sh run scan.v0.dso_sequencers > "$dso_json"

MIGRATION_ID="$(json_get "$dso_json" '.domainSequencers[0].sequencers[0].migrationId // empty')"
if [ -z "$MIGRATION_ID" ]; then
  echo "Could not derive MIGRATION_ID from scan.v0.dso_sequencers response" >&2
  exit 2
fi

before_ts="${BEFORE_TS:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
snapshot_ts_json="$SV_DIR/scan.v0.state_acs_snapshot_timestamp.json"
echo "Discovering record_time via /v0/state/acs/snapshot-timestamp..." >&2
SCAN_SCHEME="${SV_ENV[0]#*=}" \
SCAN_HOST="${SV_ENV[1]#*=}" \
SCAN_PORT="${SV_ENV[2]#*=}" \
SCAN_IP="${SV_ENV[3]#*=}" \
SCAN_PREFIX="${SV_ENV[4]#*=}" \
  ./run_api.sh run scan.v0.state_acs_snapshot_timestamp -- "$before_ts" "$MIGRATION_ID" > "$snapshot_ts_json"

RECORD_TIME="$(json_get "$snapshot_ts_json" '.record_time // empty')"
if [ -z "$RECORD_TIME" ]; then
  echo "Could not derive RECORD_TIME from snapshot-timestamp response" >&2
  exit 2
fi

updates_json="$SV_DIR/scan.v2.updates.page1.json"
echo "Discovering update_id via /v2/updates (page_size=1)..." >&2
SCAN_SCHEME="${SV_ENV[0]#*=}" \
SCAN_HOST="${SV_ENV[1]#*=}" \
SCAN_PORT="${SV_ENV[2]#*=}" \
SCAN_IP="${SV_ENV[3]#*=}" \
SCAN_PREFIX="${SV_ENV[4]#*=}" \
  PAGE_SIZE=1 ./run_api.sh run scan.v2.updates -- > "$updates_json"

UPDATE_ID="$(json_get "$updates_json" '.transactions[0].update_id // empty')"
if [ -z "$UPDATE_ID" ]; then
  echo "Could not derive UPDATE_ID from /v2/updates response" >&2
  exit 2
fi

echo "Discovering first ANS entry name via /v0/ans-entries..." >&2
ans_entries_json="$SV_DIR/scan.v0.ans_entries.page1.json"
SCAN_SCHEME="${SV_ENV[0]#*=}" \
SCAN_HOST="${SV_ENV[1]#*=}" \
SCAN_PORT="${SV_ENV[2]#*=}" \
SCAN_IP="${SV_ENV[3]#*=}" \
SCAN_PREFIX="${SV_ENV[4]#*=}" \
  ./run_api.sh run scan.v0.ans_entries -- 1 "" > "$ans_entries_json"

ANS_NAME="$(json_get "$ans_entries_json" '.entries[0].name // empty')"
if [ -z "$ANS_NAME" ]; then
  # Some deployments might not have any entries; don't fail hard for the rest.
  echo "Could not derive ANS_NAME (skipping ans_entries_by_name later)" >&2
fi

echo "Discovering validator party ids via /v0/admin/validator/licenses..." >&2
LICENSE_LIMIT="${LICENSE_LIMIT:-10}"
MAX_VALIDATOR_IDS="${MAX_VALIDATOR_IDS:-5}"
LICENSES_PAGE1_JSON="$SV_DIR/scan.v0.admin_validator_licenses.page1.json"
SCAN_SCHEME="${SV_ENV[0]#*=}" \
SCAN_HOST="${SV_ENV[1]#*=}" \
SCAN_PORT="${SV_ENV[2]#*=}" \
SCAN_IP="${SV_ENV[3]#*=}" \
SCAN_PREFIX="${SV_ENV[4]#*=}" \
  LIMIT="$LICENSE_LIMIT" ./run_api.sh run scan.v0.admin_validator_licenses -- > "$LICENSES_PAGE1_JSON"

mapfile -t VALIDATOR_PARTY_IDS < <(jq -r --argjson max "$MAX_VALIDATOR_IDS" '
  (.validator_licenses[]?.payload.validator // empty)
  | select(length>0)
' "$LICENSES_PAGE1_JSON" | head -n "$MAX_VALIDATOR_IDS")

if [ "${#VALIDATOR_PARTY_IDS[@]}" -eq 0 ]; then
  echo "Could not derive any validator party ids from licenses response" >&2
  exit 2
fi

VALIDATOR_PARTY_ID="${VALIDATOR_PARTY_IDS[0]}"
VALIDATOR_IDS_CSV="$(IFS=,; echo "${VALIDATOR_PARTY_IDS[*]}")"

echo "Mapping validator party id -> participant_id via /v0/domains/{domain_id}/parties/{party_id}/participant-id..." >&2
participant_json="$SV_DIR/scan.v0.domains_party_participant_id.json"
SCAN_SCHEME="${SV_ENV[0]#*=}" \
SCAN_HOST="${SV_ENV[1]#*=}" \
SCAN_PORT="${SV_ENV[2]#*=}" \
SCAN_IP="${SV_ENV[3]#*=}" \
SCAN_PREFIX="${SV_ENV[4]#*=}" \
  ./run_api.sh run scan.v0.domains_party_participant_id -- "$DOMAIN_ID" "$VALIDATOR_PARTY_ID" > "$participant_json"

PARTICIPANT_ID="$(json_get "$participant_json" '.participant_id // empty')"
if [ -z "$PARTICIPANT_ID" ]; then
  echo "Could not derive participant_id" >&2
  exit 2
fi
MEMBER_ID="$PARTICIPANT_ID"

echo "Derived parameters:"
{
  echo "DOMAIN_ID=$DOMAIN_ID"
  echo "MIGRATION_ID=$MIGRATION_ID"
  echo "RECORD_TIME=$RECORD_TIME"
  echo "UPDATE_ID=$UPDATE_ID"
  echo "VALIDATOR_PARTY_IDS=$(printf '%s,' "${VALIDATOR_PARTY_IDS[@]}")"
  echo "PARTICIPANT_ID=$PARTICIPANT_ID"
} > "$DATA_DIR/run-$RUN_ID/derived_params.txt"

export DOMAIN_ID MIGRATION_ID RECORD_TIME UPDATE_ID OWNER_PARTY_IDS="$VALIDATOR_IDS_CSV" \
  PARTY_ID="$VALIDATOR_PARTY_ID" VALIDATOR_IDS="$VALIDATOR_IDS_CSV" MEMBER_ID="$MEMBER_ID" \
  BEFORE_TS="$before_ts" ANS_NAME

echo "Storing all Scan API endpoint scripts..." >&2

shopt -s globstar nullglob
mapfile -t SCAN_SCRIPT_PATHS < <(printf '%s\n' api/scan/**/*.sh | sort)

for script_path in "${SCAN_SCRIPT_PATHS[@]}"; do
  rel="${script_path#api/}"
  name="${rel%.sh}"
  name="${name//\//.}"

  # Avoid overwriting dependency-captured files; skip if present.
  out="$SV_DIR/$name.json"
  if [ -f "$out" ]; then
    continue
  fi

  # Supply args/env for the handful of positional-arg scripts.
  args=()
  case "$name" in
    scan.v0.state_acs_snapshot_timestamp)
      args=("$before_ts" "$MIGRATION_ID")
      ;;
    scan.v0.state_acs_snapshot_timestamp_after)
      args=("$RECORD_TIME" "$MIGRATION_ID")
      ;;
    scan.v0.events_by_update_id)
      args=("$UPDATE_ID")
      ;;
    scan.v2.updates_tx)
      args=("$UPDATE_ID")
      ;;
    scan.v0.ans_entries_by_name)
      if [ -n "${ANS_NAME:-}" ]; then args=("$ANS_NAME"); else continue; fi
      ;;
    scan.v0.domains_party_participant_id)
      args=("$DOMAIN_ID" "$VALIDATOR_PARTY_ID")
      ;;
    scan.v0.ans_entries)
      # keep page_size=50 default for full coverage; dependencies already captured page1
      ;;
    *)
      ;;
  esac

  echo "  $name" >&2
  SCAN_SCHEME="${SV_ENV[0]#*=}" \
  SCAN_HOST="${SV_ENV[1]#*=}" \
  SCAN_PORT="${SV_ENV[2]#*=}" \
  SCAN_IP="${SV_ENV[3]#*=}" \
  SCAN_PREFIX="${SV_ENV[4]#*=}" \
    ./run_api.sh run "$name" -- "${args[@]}" > "$out"
done

echo "Scan API storage complete at: $SV_DIR" >&2

# --------
# Validator API (conventional validator wallet) - optional (auth required)
# --------

echo "Validator API storage (if auth is available)..." >&2

if [ "${SKIP_VALIDATOR_API:-0}" = "1" ]; then
  echo "SKIP_VALIDATOR_API=1; skipping conventional validator calls." >&2
  exit 0
fi

token_json="$AUTH_DIR/auth0_token_response.json"
ACCESS_TOKEN="${API_AUTH_BEARER:-}"

if [ -z "$ACCESS_TOKEN" ]; then
  echo "Attempting Auth0 token acquisition for VALIDATOR_NAME=$VALIDATOR_NAME..." >&2

  AUTH0_DOMAIN="$(awk '/^CANTON_AUTH0_DOMAIN$/{getline;print;exit}' "$ROOT_DIR/CANTON_URL_TEMPLATE.md")"
  CLIENT_ID="$(awk '/^CANTON_CLIENT_ID$/{getline;print;exit}' "$ROOT_DIR/CANTON_URL_TEMPLATE.md")"
  CLIENT_SECRET="$(awk '/^CANTON_CLIENT_SECRET$/{getline;print;exit}' "$ROOT_DIR/CANTON_URL_TEMPLATE.md")"
  AUDIENCE_TEMPLATE="$(awk '/^CANTON_AUDIENCE_TEMPLATE$/{getline;print;exit}' "$ROOT_DIR/CANTON_URL_TEMPLATE.md")"
  USERNAME="$(awk '/^CANTON_USERNAME$/{getline;print;exit}' "$ROOT_DIR/CANTON_URL_TEMPLATE.md")"
  PASSWORD="$(awk '/^CANTON_PASSWORD$/{getline;print;exit}' "$ROOT_DIR/CANTON_URL_TEMPLATE.md")"
  DB_REALM="$(awk '/^CANTON_DB_REALM$/{getline;print;exit}' "$ROOT_DIR/CANTON_URL_TEMPLATE.md")"

  AUDIENCE="$(printf '%s' "$AUDIENCE_TEMPLATE" | sed "s/{validatorName}/$VALIDATOR_NAME/g")"

  payload="$(jq -cn \
    --arg realm "$DB_REALM" \
    --arg username "$USERNAME" \
    --arg password "$PASSWORD" \
    --arg client_id "$CLIENT_ID" \
    --arg client_secret "$CLIENT_SECRET" \
    --arg audience "$AUDIENCE" \
    '{grant_type:"http://auth0.com/oauth/grant-type/password-realm", realm:$realm, username:$username, password:$password, client_id:$client_id, client_secret:$client_secret, audience:$audience, scope:"openid profile email"}')"

  # Do not print the token or the payload.
  curl -sS -X POST "$AUTH0_DOMAIN" -H "Content-Type: application/json" --data-binary "$payload" > "$token_json" || true

  ACCESS_TOKEN="$(json_get "$token_json" '.access_token // empty')"
  if [ -z "$ACCESS_TOKEN" ]; then
    echo "Auth0 token acquisition failed; skipping validator API calls. (error saved to $token_json)" >&2
    exit 0
  fi
fi

export API_AUTH_BEARER="$ACCESS_TOKEN"

# Conventional validator base URL (from CANTON_URL_TEMPLATE.md):
#   http://canton.api.nodeops.ninja/{validatorName}/api/validator/...
#
# Our http.sh validator_url is:
#   {scheme}://{host}:{port}{validator_prefix}{path}
#
VALIDATOR_SCHEME="${VALIDATOR_SCHEME:-http}"
VALIDATOR_HOST="${VALIDATOR_HOST:-canton.api.nodeops.ninja}"
VALIDATOR_PORT="${VALIDATOR_PORT:-80}"
VALIDATOR_PREFIX="${VALIDATOR_PREFIX:-/$VALIDATOR_NAME/api/validator}"

export API_USE_RESOLVE="${API_USE_RESOLVE:-0}"

shopt -s globstar nullglob
mapfile -t VALIDATOR_SCRIPT_PATHS < <(printf '%s\n' api/validator/**/*.sh | sort)

# Include api/validator scripts in run_api.sh index lookup.
export API_INCLUDE_VALIDATOR=1

for script_path in "${VALIDATOR_SCRIPT_PATHS[@]}"; do
  rel="${script_path#api/}"
  name="${rel%.sh}"
  name="${name//\//.}"

  out="$VALIDATOR_DIR/$name.json"
  if [ -f "$out" ]; then
    continue
  fi

  echo "  $name" >&2
  VALIDATOR_SCHEME="$VALIDATOR_SCHEME" \
  VALIDATOR_HOST="$VALIDATOR_HOST" \
  VALIDATOR_PORT="$VALIDATOR_PORT" \
  VALIDATOR_PREFIX="$VALIDATOR_PREFIX" \
  ./run_api.sh run "$name" -- > "$out"
done

echo "Validator API storage complete at: $VALIDATOR_DIR" >&2

