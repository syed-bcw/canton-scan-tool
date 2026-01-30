#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required" >&2
  exit 3
fi

OUT_BASE="${OUT_BASE:-out}"

pick_latest_run_dir() {
  local latest
  latest="$(ls -1 "${OUT_BASE}" 2>/dev/null | grep -E '^run-[0-9]{8}T[0-9]{6}Z$' | sort | tail -n 1 || true)"
  if [[ -z "$latest" ]]; then
    echo "No ${OUT_BASE}/run-* folders found" >&2
    exit 2
  fi
  printf "%s/%s" "$OUT_BASE" "$latest"
}

RUN_DIR="${1:-}"
if [[ -z "$RUN_DIR" ]]; then
  RUN_DIR="$(pick_latest_run_dir)"
fi

if [[ ! -d "$RUN_DIR" ]]; then
  echo "Run dir not found: $RUN_DIR" >&2
  exit 2
fi

INDEX_FILE="$RUN_DIR/_index.json"
DISCOVERY_FILE="$RUN_DIR/_discovery.json"
REPORT_FILE="$RUN_DIR/_report.json"

if [[ ! -f "$INDEX_FILE" ]]; then
  echo "Missing index: $INDEX_FILE" >&2
  exit 2
fi

RUN_BASENAME="$(basename "$RUN_DIR")"
CLEAN_DIR="${OUT_BASE}/clean-${RUN_BASENAME}"

rm -rf "$CLEAN_DIR"
mkdir -p "$CLEAN_DIR/responses" "$CLEAN_DIR/errors" "$CLEAN_DIR/meta"

# Copy run-level metadata
cp "$INDEX_FILE" "$CLEAN_DIR/index.json"
if [[ -f "$DISCOVERY_FILE" ]]; then cp "$DISCOVERY_FILE" "$CLEAN_DIR/discovery.json"; fi
if [[ -f "$REPORT_FILE" ]]; then cp "$REPORT_FILE" "$CLEAN_DIR/report.json"; fi

# Create a simple CSV manifest
{
  echo "name,exit_code,valid_json,cmd,stdout_file,stderr_file"
  jq -r '.[] | [
      .name,
      (.exit_code|tostring),
      (.valid_json|tostring),
      .cmd,
      .stdout,
      .stderr
    ] | @csv' "$INDEX_FILE"
} >"$CLEAN_DIR/manifest.csv"

# Create a human-readable markdown table
{
  echo "# Clean API Output (${RUN_BASENAME})"
  echo
  echo "## Manifest"
  echo
  echo "| API | exit | json | output | error |"
  echo "|---|---:|:---:|---|---|"
  jq -r '.[] |
    (.valid_json | if . == true then "json" else "txt" end) as $ext |
    "| \(.name) | \(.exit_code) | \(.valid_json) | responses/\(.name).\($ext) | errors/\(.name).stderr |"' "$INDEX_FILE"
} >"$CLEAN_DIR/README.md"

# For each endpoint, copy stdout/stderr and keep the original meta
jq -r '.[].name' "$INDEX_FILE" | while IFS= read -r name; do
  [[ -n "$name" ]] || continue

  meta_src="$RUN_DIR/${name}.meta.json"
  out_src="$RUN_DIR/${name}.out"
  err_src="$RUN_DIR/${name}.stderr"

  if [[ -f "$meta_src" ]]; then
    cp "$meta_src" "$CLEAN_DIR/meta/${name}.meta.json"
  fi

  # Always copy stderr (even if empty)
  if [[ -f "$err_src" ]]; then
    cp "$err_src" "$CLEAN_DIR/errors/${name}.stderr"
  else
    : >"$CLEAN_DIR/errors/${name}.stderr"
  fi

  # Normalize stdout: pretty JSON if valid, else raw text
  if [[ -f "$out_src" ]]; then
    if jq -e . <"$out_src" >/dev/null 2>&1; then
      jq . <"$out_src" >"$CLEAN_DIR/responses/${name}.json"
    else
      cp "$out_src" "$CLEAN_DIR/responses/${name}.txt"
    fi
  else
    : >"$CLEAN_DIR/responses/${name}.txt"
  fi

done

echo "Wrote clean folder: $CLEAN_DIR" >&2
