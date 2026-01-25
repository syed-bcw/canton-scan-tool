#!/usr/bin/env sh

set -eu

# Summarize output from GET /v0/admin/validator/licenses (Scan API)
# Usage:
#   ./run_api.sh run flows.validator_licenses_summary
#   ./run_api.sh run flows.validator_licenses_summary -- path/to/file.json

FILE_PATH="${1:-validator_license_out.json}"

if [ ! -f "$FILE_PATH" ]; then
  echo "File not found: $FILE_PATH" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for this script" >&2
  exit 3
fi

count=$(jq '.validator_licenses | length' "$FILE_PATH")
next=$(jq -r '.next_page_token // empty' "$FILE_PATH")

printf "validator_licenses: %s\n" "$count"
if [ -n "$next" ]; then
  printf "next_page_token: %s\n" "$next"
else
  printf "next_page_token: <none>\n"
fi

printf "\nUnique dso values:\n"
jq -r '.validator_licenses[].payload.dso' "$FILE_PATH" | sort -u | sed 's/^/  - /'

printf "\nUnique sponsor values (top 20):\n"
jq -r '.validator_licenses[].payload.sponsor' "$FILE_PATH" | sort | uniq -c | sort -nr | head -n 20 | sed 's/^/  /'

printf "\nUnique validator values (top 20):\n"
jq -r '.validator_licenses[].payload.validator' "$FILE_PATH" | sort | uniq -c | sort -nr | head -n 20 | sed 's/^/  /'
