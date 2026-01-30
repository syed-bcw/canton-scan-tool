#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../_lib/http.sh"

# GET /v0/validators/validator-faucets?validator_ids=...
#
# Env:
#   VALIDATOR_IDS=... (required; comma-separated party IDs)

if [ -z "${VALIDATOR_IDS:-}" ]; then
  echo "VALIDATOR_IDS is required (comma-separated)" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for URL encoding" >&2
  exit 3
fi

# The API expects repeated query params (validator_ids=a&validator_ids=b), not a single comma-delimited string.
query=""
old_ifs="$IFS"
IFS=','
for raw in $VALIDATOR_IDS; do
  v=$(printf "%s" "$raw" | sed 's/^ *//; s/ *$//')
  [ -n "$v" ] || continue
  v_enc=$(jq -rn --arg v "$v" '$v|@uri')
  if [ -z "$query" ]; then
    query="validator_ids=${v_enc}"
  else
    query="${query}&validator_ids=${v_enc}"
  fi
done
IFS="$old_ifs"

if [ -z "$query" ]; then
  echo "VALIDATOR_IDS did not contain any non-empty IDs" >&2
  exit 2
fi
scan_get "/v0/validators/validator-faucets?${query}"
