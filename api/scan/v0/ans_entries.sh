#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../_lib/http.sh"

# GET /v0/ans-entries
# Optional env / args:
#   PAGE_SIZE=50 (required by API; default set here)
#   NAME_PREFIX=... (optional)
#
# Usage:
#   NAME_PREFIX=alice PAGE_SIZE=20 ./run_api.sh run scan.v0.ans_entries

PAGE_SIZE="${1:-${PAGE_SIZE:-50}}"
NAME_PREFIX="${2:-${NAME_PREFIX:-}}"

if ! echo "$PAGE_SIZE" | grep -qE '^[0-9]+$'; then
  echo "PAGE_SIZE must be an integer" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for URL encoding" >&2
  exit 3
fi

page_size_enc=$(jq -rn --arg v "$PAGE_SIZE" '$v|@uri')

if [ -n "$NAME_PREFIX" ]; then
  name_prefix_enc=$(jq -rn --arg v "$NAME_PREFIX" '$v|@uri')
  scan_get "/v0/ans-entries?page_size=${page_size_enc}&name_prefix=${name_prefix_enc}"
else
  scan_get "/v0/ans-entries?page_size=${page_size_enc}"
fi
