#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DATA_DIR="${DATA_DIR:-$ROOT_DIR/data}"
RUN_ID="${RUN_ID:-$(date -u +%Y%m%dT%H%M%SZ)}"
OUT_ROOT="$DATA_DIR/run-$RUN_ID"

SV_DIR="$OUT_ROOT/sv"
SV_GLOBAL_DIR="$SV_DIR/global"
SV_VALIDATORS_DIR="$SV_DIR/validators"

mkdir -p "$SV_GLOBAL_DIR" "$SV_VALIDATORS_DIR"

LICENSE_PAGE_LIMIT="${LICENSE_PAGE_LIMIT:-50}"
MAX_VALIDATOR_PARTY_IDS="${MAX_VALIDATOR_PARTY_IDS:-10}"

# Heavy endpoints; keep configurable.
INCLUDE_HOLDINGS_STATE="${INCLUDE_HOLDINGS_STATE:-0}"
INCLUDE_ACS_SNAPSHOT_FOR_PARTY="${INCLUDE_ACS_SNAPSHOT_FOR_PARTY:-1}"

# Include conventional validator wallet API under each validator folder as /v.
INCLUDE_CONVENTIONAL_VALIDATOR_API="${INCLUDE_CONVENTIONAL_VALIDATOR_API:-1}"

# How far back to search for a snapshot timestamp.
BEFORE_TS="${BEFORE_TS:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"

cat > "$OUT_ROOT/README.directory_schema.md" <<'EOF'
# Directory Schema (per-validator Scan + Validator captures)

This run captures Scan API data split into:

## 1) Global (not validator-specific)
`data/run-<RUN_ID>/sv/global/`

Contains:
- discovery outputs (domain_id, migration_id, record_time, update_id, page(s) of `/v0/admin/validator/licenses`)
- `derived_params_global.txt`
- `acs_exact_record_time.txt` (if enabled)
- `scan.v2.updates.page1.json`

## 2) Per-validator captures
`data/run-<RUN_ID>/sv/validators/<validator_slug>/`

`<validator_slug>` is derived from `validator_party_id` by replacing non `[A-Za-z0-9._-]` with `_`.

Each validator folder contains two namespaces:
- `sv/` for Scan API data specific to that validator party/participant
- `v/` for conventional validator wallet API data (best effort, keyed by derived validator name)
- `validator_meta.txt` for mapping + capture metadata

### `sv/` contents
- `validator_meta.txt`
  - `validator_party_id=...`
  - `participant_id=...` (from `/v0/domains/{domain_id}/parties/{party}/participant-id`)
  - `domain_id=...`
  - `migration_id=...`
- `scan.v0.domains_party_participant_id.json`
- `scan.v0.validators_validator_faucets.json` (liveness for that single validator party id)
- `scan.v0.domains_member_traffic_status.json` (traffic status for that participant)
- `scan.v0.holdings_summary.json` (owned by that validator party id)
- `scan.v0.holdings_state.json` (only if `INCLUDE_HOLDINGS_STATE=1`)
- `scan.v0.ans_entries_by_party.json` (lookup by party id)
- `scan.v0.ans_entries_by_name.json` (only if ANS entry exists; derived from `ans_entries_by_party`)
- `scan.v0.acs_snapshot_for_party.json` (only if `INCLUDE_ACS_SNAPSHOT_FOR_PARTY=1`)

### `v/` contents
- wallet API responses from `api/validator/v0/wallet/*.sh`, e.g.:
  - `validator.v0.wallet.balance.json`
  - `validator.v0.wallet.transactions.json`
  - `validator.v0.wallet.user_status.json`
  - `validator.v0.wallet.amulets.json`
  - etc.

## 3) Index for joining
`data/run-<RUN_ID>/sv/global/validators_index.jsonl`

Each line:
`validator_party_id|validator_slug|participant_id|conventional_validator_name`

EOF

{
  echo "run_id=$RUN_ID"
  echo "max_validators=$MAX_VALIDATOR_PARTY_IDS"
  echo "license_page_limit=$LICENSE_PAGE_LIMIT"
  echo "include_holdings_state=$INCLUDE_HOLDINGS_STATE"
  echo "include_acs_snapshot_for_party=$INCLUDE_ACS_SNAPSHOT_FOR_PARTY"
  echo "include_conventional_validator_api=$INCLUDE_CONVENTIONAL_VALIDATOR_API"
  echo "before_ts=$BEFORE_TS"
} >> "$OUT_ROOT/README.directory_schema.md"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_cmd jq
require_cmd curl

VALIDATOR_NAME="${VALIDATOR_NAME:-arkhia}"
VALIDATOR_PARTY_IDS_CSV="${VALIDATOR_PARTY_IDS_CSV:-}"

slug_id() {
  # Keep it filesystem-safe and deterministic.
  # Example: gate-mainnetValidator-1::... -> gate-mainnetValidator-1__...
  printf '%s' "$1" | sed 's/[^A-Za-z0-9._-]/_/g'
}

json_get() {
  # Usage: json_get file jq_filter
  local file="$1"
  local filter="$2"
  jq -r "$filter" < "$file"
}

derive_validator_name_candidates() {
  # Input: validator_party_id
  # Output: newline-separated candidate validator names for URL template.
  local party="$1"
  local base
  base="${party%%::*}"
  base="$(printf '%s' "$base" | tr '[:upper:]' '[:lower:]')"

  # Candidate 1: full lowercased label
  printf '%s\n' "$base"

  # Candidate 2: drop common validator suffixes
  printf '%s\n' "$base" \
    | sed -E 's/-mainnetvalidator-1$//; s/-validator-1$//; s/-validator$//; s/-mnwallet-1$//'
}

acquire_auth0_token_for_validator() {
  # Input: validator_name
  # Output: access token to stdout (empty on failure)
  local validator_name="$1"
  local auth_out="$OUT_ROOT/auth/auth0_token_${validator_name}.json"
  mkdir -p "$OUT_ROOT/auth"

  if [ -f "$auth_out" ]; then
    jq -r '.access_token // empty' < "$auth_out"
    return 0
  fi

  local auth0_domain client_id client_secret audience_template username password db_realm audience payload
  auth0_domain="$(awk '/^CANTON_AUTH0_DOMAIN$/{getline;print;exit}' "$ROOT_DIR/CANTON_URL_TEMPLATE.md")"
  client_id="$(awk '/^CANTON_CLIENT_ID$/{getline;print;exit}' "$ROOT_DIR/CANTON_URL_TEMPLATE.md")"
  client_secret="$(awk '/^CANTON_CLIENT_SECRET$/{getline;print;exit}' "$ROOT_DIR/CANTON_URL_TEMPLATE.md")"
  audience_template="$(awk '/^CANTON_AUDIENCE_TEMPLATE$/{getline;print;exit}' "$ROOT_DIR/CANTON_URL_TEMPLATE.md")"
  username="$(awk '/^CANTON_USERNAME$/{getline;print;exit}' "$ROOT_DIR/CANTON_URL_TEMPLATE.md")"
  password="$(awk '/^CANTON_PASSWORD$/{getline;print;exit}' "$ROOT_DIR/CANTON_URL_TEMPLATE.md")"
  db_realm="$(awk '/^CANTON_DB_REALM$/{getline;print;exit}' "$ROOT_DIR/CANTON_URL_TEMPLATE.md")"

  audience="$(printf '%s' "$audience_template" | sed "s/{validatorName}/$validator_name/g")"
  payload="$(jq -cn \
    --arg realm "$db_realm" \
    --arg username "$username" \
    --arg password "$password" \
    --arg client_id "$client_id" \
    --arg client_secret "$client_secret" \
    --arg audience "$audience" \
    '{grant_type:"http://auth0.com/oauth/grant-type/password-realm", realm:$realm, username:$username, password:$password, client_id:$client_id, client_secret:$client_secret, audience:$audience, scope:"openid profile email"}')"

  curl -sS -X POST "$auth0_domain" -H "Content-Type: application/json" --data-binary "$payload" > "$auth_out" || true
  jq -r '.access_token // empty' < "$auth_out"
}

scan_env() {
  # Return the scan env as an array.
  # We rely on api/_lib/http.sh defaults, but make it explicit for clarity.
  # shellcheck disable=SC2206
  echo "SCAN_SCHEME=${SCAN_SCHEME:-https} SCAN_HOST=${SCAN_HOST:-scan.sv-1.global.canton.network.sync.global} SCAN_PORT=${SCAN_PORT:-3128} SCAN_IP=${SCAN_IP:-127.0.0.1} SCAN_PREFIX=${SCAN_PREFIX:-/api/scan}"
}

# --------
# Discover global dependency IDs (domain_id, migration_id, record_time, update_id)
# --------

SCAN_SCHEME="${SCAN_SCHEME:-https}"
SCAN_HOST="${SCAN_HOST:-scan.sv-1.global.canton.network.sync.global}"
SCAN_PORT="${SCAN_PORT:-3128}"
SCAN_IP="${SCAN_IP:-127.0.0.1}"
SCAN_PREFIX="${SCAN_PREFIX:-/api/scan}"

echo "[$RUN_ID] Discovering domain_id via /v0/scans..." >&2
SCAN_SCHEME="$SCAN_SCHEME" SCAN_HOST="$SCAN_HOST" SCAN_PORT="$SCAN_PORT" SCAN_IP="$SCAN_IP" SCAN_PREFIX="$SCAN_PREFIX" \
  ./run_api.sh run scan.v0.scans > "$SV_GLOBAL_DIR/scan.v0.scans.json"
DOMAIN_ID="$(json_get "$SV_GLOBAL_DIR/scan.v0.scans.json" '.scans[0].domainId // empty')"
if [ -z "$DOMAIN_ID" ]; then
  echo "Could not derive DOMAIN_ID" >&2
  exit 2
fi

echo "[$RUN_ID] Discovering migration_id via /v0/dso-sequencers..." >&2
SCAN_SCHEME="$SCAN_SCHEME" SCAN_HOST="$SCAN_HOST" SCAN_PORT="$SCAN_PORT" SCAN_IP="$SCAN_IP" SCAN_PREFIX="$SCAN_PREFIX" \
  ./run_api.sh run scan.v0.dso_sequencers > "$SV_GLOBAL_DIR/scan.v0.dso_sequencers.json"
MIGRATION_ID="$(json_get "$SV_GLOBAL_DIR/scan.v0.dso_sequencers.json" '.domainSequencers[0].sequencers[0].migrationId // empty')"
if [ -z "$MIGRATION_ID" ]; then
  echo "Could not derive MIGRATION_ID" >&2
  exit 2
fi

echo "[$RUN_ID] Discovering snapshot record_time via /v0/state/acs/snapshot-timestamp..." >&2
SCAN_SCHEME="$SCAN_SCHEME" SCAN_HOST="$SCAN_HOST" SCAN_PORT="$SCAN_PORT" SCAN_IP="$SCAN_IP" SCAN_PREFIX="$SCAN_PREFIX" \
  ./run_api.sh run scan.v0.state_acs_snapshot_timestamp -- "$BEFORE_TS" "$MIGRATION_ID" > "$SV_GLOBAL_DIR/scan.v0.state_acs_snapshot_timestamp.json"
RECORD_TIME="$(json_get "$SV_GLOBAL_DIR/scan.v0.state_acs_snapshot_timestamp.json" '.record_time // empty')"
if [ -z "$RECORD_TIME" ]; then
  echo "Could not derive RECORD_TIME" >&2
  exit 2
fi

echo "[$RUN_ID] Discovering update_id via /v2/updates (page_size=1)..." >&2
SCAN_SCHEME="$SCAN_SCHEME" SCAN_HOST="$SCAN_HOST" SCAN_PORT="$SCAN_PORT" SCAN_IP="$SCAN_IP" SCAN_PREFIX="$SCAN_PREFIX" \
  PAGE_SIZE=1 ./run_api.sh run scan.v2.updates -- > "$SV_GLOBAL_DIR/scan.v2.updates.page1.json"
UPDATE_ID="$(json_get "$SV_GLOBAL_DIR/scan.v2.updates.page1.json" '.transactions[0].update_id // empty')"
if [ -z "$UPDATE_ID" ]; then
  echo "Could not derive UPDATE_ID" >&2
  exit 2
fi

# --------
# Discover validator party ids (with pagination) from /v0/admin/validator/licenses
# --------

VALIDATOR_PARTY_IDS=()
if [ -n "$VALIDATOR_PARTY_IDS_CSV" ]; then
  echo "[$RUN_ID] Using VALIDATOR_PARTY_IDS_CSV override..." >&2
  while IFS= read -r v; do
    [ -n "$v" ] || continue
    VALIDATOR_PARTY_IDS+=("$v")
  done < <(printf '%s' "$VALIDATOR_PARTY_IDS_CSV" | tr ',' '\n' | sed 's/^ *//; s/ *$//' | awk 'NF')
else
  echo "[$RUN_ID] Discovering up to $MAX_VALIDATOR_PARTY_IDS validator_party_ids..." >&2
  after=""
  page_idx=0

  while :; do
    page_idx=$((page_idx + 1))
    out="$SV_GLOBAL_DIR/scan.v0.admin_validator_licenses.page${page_idx}.json"

    if [ -n "$after" ]; then
      SCAN_SCHEME="$SCAN_SCHEME" SCAN_HOST="$SCAN_HOST" SCAN_PORT="$SCAN_PORT" SCAN_IP="$SCAN_IP" SCAN_PREFIX="$SCAN_PREFIX" \
        AFTER="$after" LIMIT="$LICENSE_PAGE_LIMIT" ./run_api.sh run scan.v0.admin_validator_licenses -- > "$out"
    else
      SCAN_SCHEME="$SCAN_SCHEME" SCAN_HOST="$SCAN_HOST" SCAN_PORT="$SCAN_PORT" SCAN_IP="$SCAN_IP" SCAN_PREFIX="$SCAN_PREFIX" \
        LIMIT="$LICENSE_PAGE_LIMIT" ./run_api.sh run scan.v0.admin_validator_licenses -- > "$out"
    fi

    # Append validators from this page
    while IFS= read -r v; do
      [ -n "$v" ] || continue
      VALIDATOR_PARTY_IDS+=("$v")
    done < <(jq -r '.validator_licenses[]?.payload.validator // empty' < "$out" | sort -u)

    # Trim if we already reached the requested max.
    if [ "${#VALIDATOR_PARTY_IDS[@]}" -ge "$MAX_VALIDATOR_PARTY_IDS" ]; then
      VALIDATOR_PARTY_IDS=("${VALIDATOR_PARTY_IDS[@]:0:$MAX_VALIDATOR_PARTY_IDS}")
      break
    fi

    next="$(json_get "$out" '.next_page_token // empty')"
    if [ -z "$next" ] || [ "$next" = "null" ]; then
      break
    fi
    after="$next"
  done
fi

if [ "${#VALIDATOR_PARTY_IDS[@]}" -eq 0 ]; then
  echo "No validator party ids discovered" >&2
  exit 2
fi

VALIDATOR_PARTY_IDS_UNIQ="$(printf '%s\n' "${VALIDATOR_PARTY_IDS[@]}" | sort -u | head -n "$MAX_VALIDATOR_PARTY_IDS")"

echo "[$RUN_ID] Found validator party ids: " >&2
printf '%s\n' "$VALIDATOR_PARTY_IDS_UNIQ" | nl -ba >&2

printf "domain_id=%s\nmigration_id=%s\nrecord_time=%s\nupdate_id=%s\n" \
  "$DOMAIN_ID" "$MIGRATION_ID" "$RECORD_TIME" "$UPDATE_ID" > "$SV_GLOBAL_DIR/derived_params_global.txt"

touch "$SV_GLOBAL_DIR/.done_global"

# --------
# Determine exact record_time for acs_snapshot_for_party (if needed)
# (Some deployments require more precise recordTime than /snapshot-timestamp returns.)
# We'll discover it once using the first validator_party_id, then reuse.
# --------

FIRST_VALIDATOR_PARTY_ID="$(printf '%s\n' "$VALIDATOR_PARTY_IDS_UNIQ" | head -n 1)"
ACS_EXACT_RECORD_TIME="$RECORD_TIME"

if [ "$INCLUDE_ACS_SNAPSHOT_FOR_PARTY" = "1" ]; then
  echo "[$RUN_ID] Checking exact acs record_time using first validator id..." >&2
  tmp="$SV_GLOBAL_DIR/_tmp_acs_snapshot_probe.json"
  (
    export PARTY_ID="$FIRST_VALIDATOR_PARTY_ID"
    export RECORD_TIME="$RECORD_TIME"
    export MIGRATION_ID="$MIGRATION_ID"
    ./run_api.sh run scan.v0.acs_snapshot_for_party -- > "$tmp"
  ) 2>/dev/null || true

  if jq -e 'has("error")' "$tmp" >/dev/null 2>&1; then
    # Parse: requested=<...> != recordTime=<...>.
    ACS_EXACT_RECORD_TIME="$(jq -r '.error // ""' < "$tmp" | sed -n 's/.*recordTime=\\([^ ).]*\\).*/\\1/p' | head -n 1 || true)"
  fi

  if [ -z "$ACS_EXACT_RECORD_TIME" ]; then
    ACS_EXACT_RECORD_TIME="$RECORD_TIME"
  fi

  echo "acs_exact_record_time=$ACS_EXACT_RECORD_TIME" > "$SV_GLOBAL_DIR/acs_exact_record_time.txt"
fi

echo "[$RUN_ID] Storing per-validator outputs..." >&2

index_out="$SV_GLOBAL_DIR/validators_index.jsonl"
: > "$index_out"

validator_idx=0
while IFS= read -r validator_party_id; do
  validator_idx=$((validator_idx + 1))
  [ -n "$validator_party_id" ] || continue

  slug="$(slug_id "$validator_party_id")"
  vdir="$SV_VALIDATORS_DIR/$slug"
  sv_ns="$vdir/sv"
  v_ns="$vdir/v"
  mkdir -p "$sv_ns" "$v_ns"

  meta_file="$vdir/validator_meta.txt"
  done_flag="$vdir/.done"

  if [ -f "$done_flag" ]; then
    echo "  [skip] $validator_idx: $slug" >&2
    continue
  fi

  echo "  [$validator_idx] $slug" >&2

  # 1) Map validator_party_id -> participant_id
  dom_part_file="$sv_ns/scan.v0.domains_party_participant_id.json"
  if [ ! -f "$dom_part_file" ]; then
    DOMAIN_ID="$DOMAIN_ID" ./run_api.sh run scan.v0.domains_party_participant_id -- "$DOMAIN_ID" "$validator_party_id" \
      > "$dom_part_file"
  fi
  participant_id="$(json_get "$dom_part_file" '.participant_id // empty')"

  # Persist mapping meta early (even if participant_id is empty)
  {
    echo "validator_party_id=$validator_party_id"
    echo "participant_id=$participant_id"
    echo "domain_id=$DOMAIN_ID"
    echo "migration_id=$MIGRATION_ID"
  } > "$meta_file"

  # 2) validators_validator_faucets (liveness) for just this validator id
  if [ ! -f "$sv_ns/scan.v0.validators_validator_faucets.json" ]; then
    export VALIDATOR_IDS="$validator_party_id"
    ./run_api.sh run scan.v0.validators_validator_faucets -- > "$sv_ns/scan.v0.validators_validator_faucets.json"
  fi

  # 3) domains_member_traffic_status (requires participant_id)
  if [ -n "$participant_id" ] && [ ! -f "$sv_ns/scan.v0.domains_member_traffic_status.json" ]; then
    export DOMAIN_ID="$DOMAIN_ID"
    export MEMBER_ID="$participant_id"
    ./run_api.sh run scan.v0.domains_member_traffic_status -- > "$sv_ns/scan.v0.domains_member_traffic_status.json"
  fi

  # 4) holdings_summary and holdings_state
  export MIGRATION_ID="$MIGRATION_ID"
  export RECORD_TIME="$RECORD_TIME"
  export RECORD_TIME_MATCH="${RECORD_TIME_MATCH:-exact}"
  export OWNER_PARTY_IDS="$validator_party_id"

  if [ ! -f "$sv_ns/scan.v0.holdings_summary.json" ]; then
    ./run_api.sh run scan.v0.holdings_summary -- > "$sv_ns/scan.v0.holdings_summary.json"
  fi

  if [ "$INCLUDE_HOLDINGS_STATE" = "1" ] && [ ! -f "$sv_ns/scan.v0.holdings_state.json" ]; then
    ./run_api.sh run scan.v0.holdings_state -- > "$sv_ns/scan.v0.holdings_state.json"
  fi

  # 5) ANS entry (by party) and (optionally) by name
  ans_by_party="$sv_ns/scan.v0.ans_entries_by_party.json"
  if [ ! -f "$ans_by_party" ]; then
    ./run_api.sh run scan.v0.ans_entries_by_party -- "$validator_party_id" > "$ans_by_party"
  fi

  ans_name="$(jq -r '.entry.name // empty' < "$ans_by_party" 2>/dev/null || true)"
  if [ -n "$ans_name" ] && [ ! -f "$sv_ns/scan.v0.ans_entries_by_name.json" ]; then
    ./run_api.sh run scan.v0.ans_entries_by_name -- "$ans_name" > "$sv_ns/scan.v0.ans_entries_by_name.json"
  fi

  # 6) ACS snapshot for this validator party
  if [ "$INCLUDE_ACS_SNAPSHOT_FOR_PARTY" = "1" ]; then
    if [ ! -f "$sv_ns/scan.v0.acs_snapshot_for_party.json" ]; then
      export PARTY_ID="$validator_party_id"
      export RECORD_TIME="$ACS_EXACT_RECORD_TIME"
      ./run_api.sh run scan.v0.acs_snapshot_for_party -- > "$sv_ns/scan.v0.acs_snapshot_for_party.json"
    fi
  fi

  # 7) Conventional validator wallet API (best effort): store into ./v
  conventional_validator_name=""
  if [ "$INCLUDE_CONVENTIONAL_VALIDATOR_API" = "1" ]; then
    mapfile -t name_candidates < <(derive_validator_name_candidates "$validator_party_id" | awk 'NF>0' | awk '!seen[$0]++')
    for cand in "${name_candidates[@]}"; do
      [ -n "$cand" ] || continue
      token="$(acquire_auth0_token_for_validator "$cand" || true)"
      if [ -z "$token" ]; then
        continue
      fi

      # Probe one endpoint to validate this candidate before full run.
      probe_file="$v_ns/_probe_user_status_${cand}.json"
      API_INCLUDE_VALIDATOR=1 API_USE_RESOLVE=0 API_AUTH_BEARER="$token" \
      VALIDATOR_SCHEME=http VALIDATOR_HOST=canton.api.nodeops.ninja VALIDATOR_PORT=80 VALIDATOR_PREFIX="/$cand/api/validator" \
        ./run_api.sh run validator.v0.wallet.user_status -- > "$probe_file" 2>/dev/null || true

      if jq -e 'has("party_id") or has("user_status") or has("user_onboarded")' "$probe_file" >/dev/null 2>&1; then
        conventional_validator_name="$cand"
        break
      fi
    done

    if [ -n "$conventional_validator_name" ]; then
      token="$(acquire_auth0_token_for_validator "$conventional_validator_name" || true)"
      if [ -n "$token" ]; then
        # Run all validator wallet scripts and store under v namespace.
        while IFS= read -r vs_path; do
          [ -n "$vs_path" ] || continue
          rel="${vs_path#api/}"
          name="${rel%.sh}"
          name="${name//\//.}"
          out="$v_ns/$name.json"
          if [ -f "$out" ]; then
            continue
          fi
          API_INCLUDE_VALIDATOR=1 API_USE_RESOLVE=0 API_AUTH_BEARER="$token" \
          VALIDATOR_SCHEME=http VALIDATOR_HOST=canton.api.nodeops.ninja VALIDATOR_PORT=80 VALIDATOR_PREFIX="/$conventional_validator_name/api/validator" \
            ./run_api.sh run "$name" -- > "$out" 2>/dev/null || true
        done < <(printf '%s\n' api/validator/v0/wallet/*.sh | sort)
      fi
    fi
  fi

  echo "done" > "$done_flag"

  echo "$validator_party_id|$slug|$participant_id|$conventional_validator_name" >> "$index_out"
done < <(printf '%s\n' "$VALIDATOR_PARTY_IDS_UNIQ")

echo "[$RUN_ID] Per-validator storage complete. See: $SV_VALIDATORS_DIR" >&2

# --------
# Wallet API storage is not repeated per validator_party_id because it depends on the authenticated user/validator host.
# If you want wallet data partitioned by validator host, run_exhaustive_store.sh already does that.
# --------

