#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../_lib/http.sh"

# POST /v0/open-and-issuing-mining-rounds
#
# Env:
#   PAYLOAD='{"cached_open_mining_round_contract_ids":[],"cached_issuing_round_contract_ids":[]}' (optional)

payload="${PAYLOAD:-}"

if [ -z "$payload" ]; then
	payload='{"cached_open_mining_round_contract_ids":[],"cached_issuing_round_contract_ids":[]}'
fi

scan_post_json "/v0/open-and-issuing-mining-rounds" "$payload"
