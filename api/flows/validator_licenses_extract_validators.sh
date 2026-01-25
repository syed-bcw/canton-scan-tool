#!/usr/bin/env sh

set -eu

# Emit unique validator party IDs from validator license output.
# Usage:
#   ./run_api.sh run flows.validator_licenses_extract_validators
#   ./run_api.sh run flows.validator_licenses_extract_validators -- validator_license_out.json

FILE_PATH="${1:-validator_license_out.json}"

if [ ! -f "$FILE_PATH" ]; then
  echo "File not found: $FILE_PATH" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for this script" >&2
  exit 3
fi

jq -r '.validator_licenses[].payload.validator' "$FILE_PATH" | sort -u
