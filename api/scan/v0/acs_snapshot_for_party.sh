#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../_lib/http.sh"

if [ -z "${PARTY_ID:-}" ]; then
  echo "PARTY_ID is required (party to fetch ACS snapshot for)" >&2
  exit 2
fi

if [ -z "${RECORD_TIME:-}" ]; then
  echo "RECORD_TIME is required (query param used by /v0/acs/{party})" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for URL encoding" >&2
  exit 3
fi

party_enc="$(jq -rn --arg v "$PARTY_ID" '$v|@uri')"
record_time_enc="$(jq -rn --arg v "$RECORD_TIME" '$v|@uri')"

# GET /v0/acs/{party}?record_time=<...> (deprecated)
scan_get "/v0/acs/${party_enc}?record_time=${record_time_enc}"

