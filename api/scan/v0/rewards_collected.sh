#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../_lib/http.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required to derive round" >&2
  exit 3
fi

# GET /v0/rewards-collected?round=<round> (deprecated)
# If ROUND is not provided, derive it from /v0/round-of-latest-data.
round="${ROUND:-}"
if [ -z "$round" ]; then
  round="$(scan_get "/v0/round-of-latest-data" | jq -r '.round // empty')"
fi

if [ -z "$round" ]; then
  echo "Could not determine round; set ROUND=... or ensure /v0/round-of-latest-data works" >&2
  exit 2
fi

scan_get "/v0/rewards-collected?round=${round}"

