#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../_lib/http.sh"

# GET /v0/domains/{domain_id}/members/{member_id}/traffic-status
#
# Env:
#   DOMAIN_ID=... (required)
#   MEMBER_ID=... (required)

if [ -z "${DOMAIN_ID:-}" ]; then
  echo "DOMAIN_ID is required" >&2
  exit 2
fi

if [ -z "${MEMBER_ID:-}" ]; then
  echo "MEMBER_ID is required" >&2
  exit 2
fi

scan_get "/v0/domains/${DOMAIN_ID}/members/${MEMBER_ID}/traffic-status"
