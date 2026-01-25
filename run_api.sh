#!/usr/bin/env bash
# API collection runner (shell-based "Postman" style)
# Usage:
#   ./run_api.sh list
#   ./run_api.sh run <index|name> [-- extra args]
#   ./run_api.sh all [-- extra args]
#   ./run_api.sh help

set -eu

ROOT_DIR="$(dirname "$0")"
API_DIR="$ROOT_DIR/api"

help() {
  cat <<EOF
Usage: $0 <command>

Commands:
  list                List available API scripts
  run <index|name>    Run a specific script by numeric index or name
  all                 Run all discovered scripts (in order)
  help                Show this help

Examples:
  $0 list
  $0 run 1 -- --verbose
  $0 run scan.v0.scans
  $0 all
EOF
}

# Build a temporary index of scripts: index|name|path
build_index() {
  # write lines as: index|name|path into supplied tmpfile
  tmpfile="$1"
  : > "$tmpfile"
  idx=0
  # Use NUL-separated find to be robust with spaces/newlines in names
  find "$API_DIR" -type f -name '*.sh' -print0 | sort -z | while IFS= read -r -d '' path; do
    idx=$((idx + 1))
    # name: strip "$API_DIR"/ prefix, replace / with ., strip .sh
    name=${path#"$API_DIR"/}
    name=${name%.sh}
    name=$(printf "%s" "$name" | sed 's#/#.#g')
    printf "%s|%s|%s\n" "$idx" "$name" "$path" >> "$tmpfile"
  done
}

list_scripts() {
  tmp=$(mktemp)
  build_index "$tmp"
  printf "%-4s %-30s %s\n" "#" "NAME" "PATH"
  while IFS='|' read -r idx name path; do
    printf "%4s %-30s %s\n" "$idx" "$name" "$path"
  done < "$tmp"
  rm -f "$tmp"
}

find_script() {
  key="$1"
  tmp=$(mktemp)
  build_index "$tmp"
  script_path=""
  if printf "%s" "$key" | grep -qE '^[0-9]+$'; then
    # numeric index lookup
    script_path=$(awk -F'|' -v k="$key" '$1==k {print $3; exit}' "$tmp" || true)
  else
    # exact name match
    script_path=$(awk -F'|' -v k="$key" '$2==k {print $3; exit}' "$tmp" || true)
  fi
  rm -f "$tmp"
  if [ -z "$script_path" ]; then
    return 1
  fi
  printf "%s" "$script_path"
}

run_script() {
  path="$1"
  shift || true
  if [ ! -x "$path" ]; then
    sh "$path" "$@"
  else
    "$path" "$@"
  fi
}

if [ "$#" -lt 1 ]; then
  help
  exit 1
fi

cmd="$1"
shift || true

case "$cmd" in
  help)
    help
    ;;
  list)
    list_scripts
    ;;
  run)
    if [ "$#" -lt 1 ]; then
      echo "run requires an index or name" >&2
      exit 2
    fi
    target="$1"
    # collect passthrough args after optional --
    shift || true
    if [ "$#" -gt 0 ]; then
      # if first is --, drop it
      if [ "$1" = "--" ]; then
        shift || true
      fi
    fi
    script_path=$(find_script "$target" 2>/dev/null) || {
      echo "Script not found: $target" >&2
      exit 3
    }
    run_script "$script_path" "$@"
    ;;
  all)
    # collect passthrough args after optional --
    if [ "$#" -gt 0 ] && [ "$1" = "--" ]; then
      shift
    fi
    tmp=$(mktemp)
    build_index "$tmp"
    while IFS='|' read -r idx name path; do
      printf "\n### Running %s (%s)\n" "$name" "$path"
      run_script "$path" "$@"
    done < "$tmp"
    rm -f "$tmp"
    ;;
  *)
    echo "Unknown command: $cmd" >&2
    help
    exit 2
    ;;
esac

