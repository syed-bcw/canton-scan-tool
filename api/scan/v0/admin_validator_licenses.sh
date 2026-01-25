#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../_lib/http.sh"

AFTER="${AFTER:-}"
LIMIT="${LIMIT:-}"

qs=""
if [ -n "$AFTER" ]; then
  qs="${qs}${qs:+&}after=${AFTER}"
fi
if [ -n "$LIMIT" ]; then
  qs="${qs}${qs:+&}limit=${LIMIT}"
fi

path="/v0/admin/validator/licenses"
if [ -n "$qs" ]; then
  path="${path}?${qs}"
fi

# GET /v0/admin/validator/licenses?after=&limit=
scan_get "$path"
