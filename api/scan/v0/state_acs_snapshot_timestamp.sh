#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../_lib/http.sh"

# GET /v0/state/acs/snapshot-timestamp
# Required env / args:
#   BEFORE=... (timestamp string)
#   MIGRATION_ID=... (integer)

BEFORE="${1:-${BEFORE:-}}"
MIGRATION_ID="${2:-${MIGRATION_ID:-}}"

if [ -z "${BEFORE}" ] || [ -z "${MIGRATION_ID}" ]; then
  echo "Usage: $0 <before> <migration_id>" >&2
  echo "  or set BEFORE=... MIGRATION_ID=..." >&2
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

before_enc=$(jq -rn --arg v "$BEFORE" '$v|@uri')

scan_get "/v0/state/acs/snapshot-timestamp?before=${before_enc}&migration_id=${MIGRATION_ID}"
