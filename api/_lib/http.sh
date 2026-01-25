#!/usr/bin/env sh

set -eu

# Shared curl helpers for this repo.
#
# Usage from a script under api/**:
#   . "$(CDPATH= cd -- "$(dirname "$0")" && pwd)/../../_lib/http.sh"
#   scan_get "/v0/scans"
#
# Configuration (override via env):
#   SCAN_SCHEME, SCAN_HOST, SCAN_PORT, SCAN_IP, SCAN_PREFIX
#   VALIDATOR_SCHEME, VALIDATOR_HOST, VALIDATOR_PORT, VALIDATOR_IP, VALIDATOR_PREFIX
#   API_VERBOSE=1
#   API_AUTH_BEARER=... (adds Authorization header)
#   API_CURL_EXTRA="..." (extra curl args, e.g. "--connect-timeout 2")

: "${SCAN_SCHEME:=https}"
: "${SCAN_HOST:=scan.sv-1.global.canton.network.sync.global}"
: "${SCAN_PORT:=3128}"
: "${SCAN_IP:=127.0.0.1}"
: "${SCAN_PREFIX:=/api/scan}"

: "${VALIDATOR_SCHEME:=https}"
: "${VALIDATOR_HOST:=localhost}"
: "${VALIDATOR_PORT:=8080}"
: "${VALIDATOR_IP:=127.0.0.1}"
: "${VALIDATOR_PREFIX:=/api/validator}"

api__curl() {
  method="$1"
  url="$2"
  resolve="$3"
  shift 3

  payload="${1:-}"

  set -- curl -sS --location -X "$method" \
    --resolve "$resolve" \
    --noproxy "*" \
    -H "Accept: application/json"

  if [ "${API_VERBOSE:-0}" = "1" ]; then
    set -- "$@" -v
  fi

  if [ -n "${API_AUTH_BEARER:-}" ]; then
    set -- "$@" -H "Authorization: Bearer ${API_AUTH_BEARER}"
  fi

  if [ -n "${API_CURL_EXTRA:-}" ]; then
    # shellcheck disable=SC2086
    set -- "$@" ${API_CURL_EXTRA}
  fi

  if [ -n "$payload" ]; then
    set -- "$@" -H "Content-Type: application/json" --data-binary "$payload"
  fi

  set -- "$@" "$url"

  "$@"
}

scan_url() {
  path="$1"
  printf "%s://%s:%s%s%s" "$SCAN_SCHEME" "$SCAN_HOST" "$SCAN_PORT" "$SCAN_PREFIX" "$path"
}

validator_url() {
  path="$1"
  printf "%s://%s:%s%s%s" "$VALIDATOR_SCHEME" "$VALIDATOR_HOST" "$VALIDATOR_PORT" "$VALIDATOR_PREFIX" "$path"
}

scan_get() {
  path="$1"
  api__curl GET "$(scan_url "$path")" "$SCAN_HOST:$SCAN_PORT:$SCAN_IP"
}

scan_post_json() {
  path="$1"
  json="$2"
  api__curl POST "$(scan_url "$path")" "$SCAN_HOST:$SCAN_PORT:$SCAN_IP" "$json"
}

validator_get() {
  path="$1"
  api__curl GET "$(validator_url "$path")" "$VALIDATOR_HOST:$VALIDATOR_PORT:$VALIDATOR_IP"
}

validator_post_json() {
  path="$1"
  json="$2"
  api__curl POST "$(validator_url "$path")" "$VALIDATOR_HOST:$VALIDATOR_PORT:$VALIDATOR_IP" "$json"
}
