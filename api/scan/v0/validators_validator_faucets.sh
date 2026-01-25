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

scan_get "/v0/validators/validator-faucets?validator_ids=${VALIDATOR_IDS}"
