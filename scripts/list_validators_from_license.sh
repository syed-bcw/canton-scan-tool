#!/usr/bin/env bash
set -euo pipefail

LICENSE_FILE=${1:-validator_license_out.json}
LIMIT=${2:-0}

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 1
fi

if [[ ! -f "$LICENSE_FILE" ]]; then
  echo "ERROR: license file not found: $LICENSE_FILE" >&2
  exit 1
fi

cmd=(jq -r '.validator_licenses[].payload.validator' "$LICENSE_FILE" | sort | uniq)

if [[ "$LIMIT" != "0" ]]; then
  eval "${cmd[*]}" | head -n "$LIMIT"
else
  eval "${cmd[*]}"
fi
