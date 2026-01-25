#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../_lib/http.sh"

# Resolve participant IDs for validator party IDs found in validator license output.
#
# Usage:
#   ./run_api.sh run flows.scan_participant_ids_for_validators -- validator_license_out.json
#
# Env:
#   DOMAIN_ID=...   (optional; if unset, first domainId from /v0/scans is used)
#   LIMIT_VALIDATORS=... (optional; limit number of validators processed)

FILE_PATH="${1:-validator_license_out.json}"

if [ ! -f "$FILE_PATH" ]; then
  echo "File not found: $FILE_PATH" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 3
fi

if [ -n "${DOMAIN_ID:-}" ]; then
  domain_id="$DOMAIN_ID"
else
  domain_id=$(scan_get "/v0/scans" | jq -r '.scans[0].domainId // empty')
fi

if [ -z "$domain_id" ]; then
  echo "Could not determine DOMAIN_ID (set DOMAIN_ID=... or ensure /v0/scans returns one)" >&2
  exit 4
fi

domain_id_enc=$(jq -rn --arg v "$domain_id" '$v|@uri')

validators=$(jq -r '.validator_licenses[].payload.validator' "$FILE_PATH" | sort -u)

if [ -n "${LIMIT_VALIDATORS:-}" ]; then
  validators=$(printf "%s\n" "$validators" | head -n "$LIMIT_VALIDATORS")
fi

# Output JSON lines for easy downstream processing.
# {"domain_id": "...", "validator_party_id": "...", "participant_id": "..."}

printf "%s" "$validators" | while IFS= read -r validator_party; do
  [ -n "$validator_party" ] || continue

  party_enc=$(jq -rn --arg v "$validator_party" '$v|@uri')

  resp=$(scan_get "/v0/domains/${domain_id_enc}/parties/${party_enc}/participant-id" || true)

  participant_id=$(printf "%s" "$resp" | jq -r '.participant_id // empty' 2>/dev/null || true)

  if [ -n "$participant_id" ]; then
    jq -cn --arg domain_id "$domain_id" --arg validator_party_id "$validator_party" --arg participant_id "$participant_id" \
      '{domain_id:$domain_id, validator_party_id:$validator_party_id, participant_id:$participant_id}'
  else
    # Emit error record with raw response (best-effort)
    jq -cn --arg domain_id "$domain_id" --arg validator_party_id "$validator_party" --arg response "$resp" \
      '{domain_id:$domain_id, validator_party_id:$validator_party_id, error:true, response:$response}'
  fi

done
