#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../_lib/http.sh"

DOMAIN_ID="${1:-${DOMAIN_ID:-}}"
PARTY_ID="${2:-${PARTY_ID:-}}"

if [ -z "${DOMAIN_ID}" ] || [ -z "${PARTY_ID}" ]; then
  echo "Usage: $0 <domain_id> <party_id>" >&2
  echo "  or set DOMAIN_ID=... PARTY_ID=..." >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for URL encoding" >&2
  exit 3
fi

domain_id_enc=$(jq -rn --arg v "$DOMAIN_ID" '$v|@uri')
party_id_enc=$(jq -rn --arg v "$PARTY_ID" '$v|@uri')

# GET /v0/domains/{domain_id}/parties/{party_id}/participant-id
scan_get "/v0/domains/${domain_id_enc}/parties/${party_id_enc}/participant-id"
