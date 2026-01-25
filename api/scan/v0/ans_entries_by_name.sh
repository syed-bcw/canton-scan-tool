#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../_lib/http.sh"

NAME="${1:-${NAME:-}}"

if [ -z "${NAME}" ]; then
  echo "Usage: $0 <name>" >&2
  echo "  or set NAME=..." >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for URL encoding" >&2
  exit 3
fi

name_enc=$(jq -rn --arg v "$NAME" '$v|@uri')

# GET /v0/ans-entries/by-name/{name}
scan_get "/v0/ans-entries/by-name/${name_enc}"
