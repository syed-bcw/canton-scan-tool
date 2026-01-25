#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../../_lib/http.sh"

# GET /v0/wallet/user-status
validator_get "/v0/wallet/user-status"
