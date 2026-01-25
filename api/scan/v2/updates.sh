#!/usr/bin/env sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/../../_lib/http.sh"

# POST /v2/updates
# Optional env:
#   PAGE_SIZE=100
#   AFTER_MIGRATION_ID=...
#   AFTER_RECORD_TIME=... (string)
#   DAML_VALUE_ENCODING=compact_json

PAGE_SIZE="${PAGE_SIZE:-100}"
DAML_VALUE_ENCODING="${DAML_VALUE_ENCODING:-compact_json}"
AFTER_MIGRATION_ID="${AFTER_MIGRATION_ID:-}"
AFTER_RECORD_TIME="${AFTER_RECORD_TIME:-}"

if [ -n "$AFTER_MIGRATION_ID" ] && [ -z "$AFTER_RECORD_TIME" ]; then
  echo "AFTER_RECORD_TIME is required when AFTER_MIGRATION_ID is set" >&2
  exit 2
fi

if [ -z "$AFTER_MIGRATION_ID" ]; then
  payload=$(cat <<EOF
{"page_size": ${PAGE_SIZE}, "daml_value_encoding": "${DAML_VALUE_ENCODING}"}
EOF
)
else
  payload=$(cat <<EOF
{"after": {"after_migration_id": ${AFTER_MIGRATION_ID}, "after_record_time": "${AFTER_RECORD_TIME}"}, "page_size": ${PAGE_SIZE}, "daml_value_encoding": "${DAML_VALUE_ENCODING}"}
EOF
)
fi

scan_post_json "/v2/updates" "$payload"
