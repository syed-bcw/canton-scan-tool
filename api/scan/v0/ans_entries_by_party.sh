#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../_lib/http.sh"

PARTY_ID="${1:-${PARTY_ID:-}}"

if [ -z "${PARTY_ID}" ]; then
  echo "Usage: $0 <party_id>" >&2
  echo "  or set PARTY_ID=..." >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for URL encoding" >&2
  exit 3
fi

party_id_enc=$(jq -rn --arg v "$PARTY_ID" '$v|@uri')

# GET /v0/ans-entries/by-party/{party}
scan_get "/v0/ans-entries/by-party/${party_id_enc}"
