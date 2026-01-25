#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../_lib/http.sh"

# POST /v0/open-and-issuing-mining-rounds
#
# Env:
#   PAYLOAD='{}' (optional; defaults to {})

payload="${PAYLOAD:-{}}"

scan_post_json "/v0/open-and-issuing-mining-rounds" "$payload"
