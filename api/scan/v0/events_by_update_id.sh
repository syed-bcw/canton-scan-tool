#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../_lib/http.sh"

UPDATE_ID="${1:-${UPDATE_ID:-}}"

if [ -z "${UPDATE_ID}" ]; then
  echo "Usage: $0 <update_id>" >&2
  echo "  or set UPDATE_ID=..." >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for URL encoding" >&2
  exit 3
fi

update_id_enc=$(jq -rn --arg v "$UPDATE_ID" '$v|@uri')

# GET /v0/events/{update_id}
scan_get "/v0/events/${update_id_enc}"
