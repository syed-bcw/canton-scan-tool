#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../_lib/http.sh"

# GET /v0/state/acs/snapshot-timestamp-after
# Required env / args:
#   AFTER=... (timestamp string)
#   MIGRATION_ID=... (integer)

AFTER="${1:-${AFTER:-}}"
MIGRATION_ID="${2:-${MIGRATION_ID:-}}"

if [ -z "${AFTER}" ] || [ -z "${MIGRATION_ID}" ]; then
  echo "Usage: $0 <after> <migration_id>" >&2
  echo "  or set AFTER=... MIGRATION_ID=..." >&2
  exit 2
fi

if ! echo "$MIGRATION_ID" | grep -qE '^[0-9]+$'; then
  echo "MIGRATION_ID must be an integer" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for URL encoding" >&2
  exit 3
fi

after_enc=$(jq -rn --arg v "$AFTER" '$v|@uri')

scan_get "/v0/state/acs/snapshot-timestamp-after?after=${after_enc}&migration_id=${MIGRATION_ID}"
