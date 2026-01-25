#!/usr/bin/env bash
set -euo pipefail

LICENSE_FILE=${1:-validator_license_out.json}
OUT_DIR=${2:-out}
LIMIT=${LIMIT:-50}

AFTER_MIGRATION_ID=${AFTER_MIGRATION_ID:-3}
AFTER_RECORD_TIME=${AFTER_RECORD_TIME:-2100-01-01T00:00:00Z}
MAX_PAGES=${MAX_PAGES:-50}
PAGE_SIZE=${PAGE_SIZE:-200}

CHOICE_CONTAINS=${CHOICE_CONTAINS:-Transfer}
INCLUDE_ARGS=${INCLUDE_ARGS:-1}

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required" >&2
  exit 1
fi

if [[ ! -f "$LICENSE_FILE" ]]; then
  echo "ERROR: license file not found: $LICENSE_FILE" >&2
  exit 1
fi

if [[ ! -d "$OUT_DIR" ]]; then
  mkdir -p "$OUT_DIR"
fi

# Make sure CLI is built.
if [[ ! -f dist/cli.js ]]; then
  echo "Building TS CLI..." >&2
  npm run build >/dev/null
fi

mapfile -t VALIDATORS < <(jq -r '.validator_licenses[].payload.validator' "$LICENSE_FILE" | sort -u)

if [[ ${#VALIDATORS[@]} -eq 0 ]]; then
  echo "ERROR: no validators found in $LICENSE_FILE" >&2
  exit 1
fi

show_n=$LIMIT
if (( show_n > ${#VALIDATORS[@]} )); then
  show_n=${#VALIDATORS[@]}
fi

echo "Select a validator to scan (showing first $show_n of ${#VALIDATORS[@]}):" >&2
for ((i=0; i<show_n; i++)); do
  printf '%3d) %s\n' $((i+1)) "${VALIDATORS[$i]}" >&2
done

echo >&2
read -r -p "Enter number (1-$show_n), or type a substring to filter: " SELECTION

# If numeric selection.
if [[ "$SELECTION" =~ ^[0-9]+$ ]]; then
  idx=$((SELECTION-1))
  if (( idx < 0 || idx >= show_n )); then
    echo "ERROR: selection out of range" >&2
    exit 1
  fi
  PARTY="${VALIDATORS[$idx]}"
else
  # Substring filter.
  FILTER="$SELECTION"
  mapfile -t FILTERED < <(printf '%s\n' "${VALIDATORS[@]}" | grep -i -- "$FILTER" || true)
  if [[ ${#FILTERED[@]} -eq 0 ]]; then
    echo "ERROR: no validators match '$FILTER'" >&2
    exit 1
  fi

  show_m=${#FILTERED[@]}
  if (( show_m > 30 )); then show_m=30; fi

  echo "Matches (showing first $show_m of ${#FILTERED[@]}):" >&2
  for ((i=0; i<show_m; i++)); do
    printf '%3d) %s\n' $((i+1)) "${FILTERED[$i]}" >&2
  done
  echo >&2
  read -r -p "Enter number (1-$show_m): " SELECTION2
  if [[ ! "$SELECTION2" =~ ^[0-9]+$ ]]; then
    echo "ERROR: expected a number" >&2
    exit 1
  fi
  idx2=$((SELECTION2-1))
  if (( idx2 < 0 || idx2 >= show_m )); then
    echo "ERROR: selection out of range" >&2
    exit 1
  fi
  PARTY="${FILTERED[$idx2]}"
fi

SAFE_KEY=$(echo "$PARTY" | sed 's/::.*$//' | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/^-//;s/-$//')
TS=$(date -u +%Y%m%dT%H%M%SZ)
OUT_FILE="$OUT_DIR/${SAFE_KEY}_${TS}.jsonl"
SELECTED_FILE="$OUT_DIR/selected_validator.txt"

echo "$PARTY" > "$SELECTED_FILE"

echo "Selected: $PARTY" >&2
echo "Wrote selected party to: $SELECTED_FILE" >&2

echo "Scanning (choice contains: $CHOICE_CONTAINS) -> $OUT_FILE" >&2

ARGS=(party-updates --party "$PARTY" --after-migration-id "$AFTER_MIGRATION_ID" --after-record-time "$AFTER_RECORD_TIME" --max-pages "$MAX_PAGES" --page-size "$PAGE_SIZE" --progress)

if [[ -n "$CHOICE_CONTAINS" ]]; then
  ARGS+=(--choice-contains "$CHOICE_CONTAINS")
fi

if [[ "$INCLUDE_ARGS" == "1" ]]; then
  ARGS+=(--include-args)
fi

node dist/cli.js "${ARGS[@]}" > "$OUT_FILE"

echo "Done. Events written to: $OUT_FILE" >&2
