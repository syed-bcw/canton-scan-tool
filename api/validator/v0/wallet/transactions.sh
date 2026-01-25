#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../../_lib/http.sh"

# POST /v0/wallet/transactions
# Env:
#   PAGE_SIZE (default 100)
#   BEGIN_AFTER_ID (default null)

: "${PAGE_SIZE:=100}"
: "${BEGIN_AFTER_ID:=null}"

payload=$(cat <<EOF
{
  "page_size": ${PAGE_SIZE},
  "begin_after_id": ${BEGIN_AFTER_ID}
}
EOF
)

validator_post_json "/v0/wallet/transactions" "$payload"
