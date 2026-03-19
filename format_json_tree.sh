#!/usr/bin/env bash
set -euo pipefail

# Pretty-format JSON files recursively in a directory tree.
# Usage:
#   ./format_json_tree.sh
#   ./format_json_tree.sh data/run-20260319T171601Z
#   ./format_json_tree.sh /absolute/path/to/dir
#
# Notes:
# - Requires jq.
# - Rewrites files in-place.
# - Skips files that are not valid JSON and reports them.

ROOT_DIR="${1:-data}"

if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required (not found in PATH)." >&2
  exit 1
fi

if [ ! -d "$ROOT_DIR" ]; then
  echo "Error: directory not found: $ROOT_DIR" >&2
  exit 2
fi

formatted=0
skipped_invalid=0
skipped_unreadable=0
tmp="$(mktemp)"

cleanup() {
  rm -f "$tmp"
}
trap cleanup EXIT

# Use find via shell tool per environment conventions.
while IFS= read -r -d '' file; do
  if [ ! -r "$file" ] || [ ! -w "$file" ]; then
    echo "skip (unreadable/unwritable): $file" >&2
    skipped_unreadable=$((skipped_unreadable + 1))
    continue
  fi

  if jq . "$file" > "$tmp" 2>/dev/null; then
    # Avoid touching file if content is already identical.
    if ! cmp -s "$file" "$tmp"; then
      mv "$tmp" "$file"
      formatted=$((formatted + 1))
    fi
  else
    echo "skip (invalid json): $file" >&2
    skipped_invalid=$((skipped_invalid + 1))
  fi
done < <(find "$ROOT_DIR" -type f -name '*.json' -print0)

echo "Done."
echo "  root: $ROOT_DIR"
echo "  formatted: $formatted"
echo "  skipped_invalid: $skipped_invalid"
echo "  skipped_unreadable: $skipped_unreadable"

