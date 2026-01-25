#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../_lib/http.sh"

# POST /v0/holdings/summary
#
# This endpoint provides an aggregate, balance-like view for one or more parties.
#
# Env:
#   PARTY_ID=...                  (required unless PAYLOAD is set)
#   AS_OF_ROUND=123               (optional)
#   PAYLOAD='{"party_ids":["..."]}'  (optional; overrides generated payload)

if [ -n "${PAYLOAD:-}" ]; then
  payload="$PAYLOAD"
else
  if [ -z "${PARTY_ID:-}" ]; then
    echo "PARTY_ID is required (or set PAYLOAD)" >&2
    exit 2
  fi

  if [ -n "${AS_OF_ROUND:-}" ]; then
    payload=$(cat <<EOF
{"party_ids": ["${PARTY_ID}"], "as_of_round": ${AS_OF_ROUND}}
EOF
)
  else
    payload=$(cat <<EOF
{"party_ids": ["${PARTY_ID}"]}
EOF
)
  fi
fi

scan_post_json "/v0/holdings/summary" "$payload"
