#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../_lib/http.sh"

# POST /v0/holdings/state
#
# This endpoint returns paginated created-events for holdings-related templates.
#
# Env:
#   PARTY_ID=...                  (required unless PAYLOAD is set)
#   PAGE_SIZE=100                 (optional)
#   PAYLOAD='{"party_ids":["..."],"page_size":100}' (optional; overrides generated payload)

PAGE_SIZE="${PAGE_SIZE:-100}"

if [ -n "${PAYLOAD:-}" ]; then
  payload="$PAYLOAD"
else
  if [ -z "${PARTY_ID:-}" ]; then
    echo "PARTY_ID is required (or set PAYLOAD)" >&2
    exit 2
  fi

  payload=$(cat <<EOF
{"party_ids": ["${PARTY_ID}"], "page_size": ${PAGE_SIZE}}
EOF
)
fi

scan_post_json "/v0/holdings/state" "$payload"
