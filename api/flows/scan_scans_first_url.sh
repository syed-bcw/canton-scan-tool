#!/usr/bin/env sh

set -eu

# Flow: fetch /v0/scans and print the first scan publicUrl.
# Requires either `python3` or `jq`.

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../_lib/http.sh"

json="$(scan_get "/v0/scans")"

if command -v jq >/dev/null 2>&1; then
  printf "%s" "$json" | jq -r '.scans[0].scans[0].publicUrl // empty'
  exit 0
fi

if command -v python3 >/dev/null 2>&1; then
  printf "%s" "$json" | python3 - <<'PY'
import json, sys
try:
    data = json.load(sys.stdin)
    scans = data.get('scans') or []
    if not scans:
        sys.exit(1)
    inner = (scans[0] or {}).get('scans') or []
    if not inner:
        sys.exit(1)
    url = (inner[0] or {}).get('publicUrl')
    if url:
        print(url)
except Exception:
    sys.exit(1)
PY
  exit $?
fi

echo "Need jq or python3 to parse JSON" >&2
exit 3
