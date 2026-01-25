#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../_lib/http.sh"

# Many deployments expose common endpoints under the same prefix.
# If your Scan routes these elsewhere, override SCAN_PREFIX or call curl directly.
scan_get "/status"
