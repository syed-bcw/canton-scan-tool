Scan API calling guide (curl + scripts)
======================================

This repo is Scan-only: all examples call the Scan API under the base path `/api/scan`.

Configuration
-------------
Both the shell scripts and the Node/TS CLI use the same connection settings:

- `SCAN_HOST` (TLS hostname + HTTP Host header)
- `SCAN_PORT` (TCP port)
- `SCAN_IP` (where to connect; often `127.0.0.1` when using a local proxy)
- `SCAN_PREFIX` (default `/api/scan`)

Example:

- `export SCAN_HOST='scan.sv-1.global.canton.network.sync.global'`
- `export SCAN_PORT=3128`
- `export SCAN_IP=127.0.0.1`
- `export SCAN_PREFIX=/api/scan`

Tip: You can put these in a root `.env` file and `run_api.sh` will load it.

Option A: Use the shell "API collection"
-----------------------------------------
List scripts:
- `./run_api.sh list`

Run a script by name:
- `./run_api.sh run scan.v0.scans`

Run a script by index:
- `./run_api.sh run 1`

Full endpoint reference
-----------------------
- See `docs/SCAN_API_ENDPOINTS.md` for a per-endpoint guide: purpose, how to call, and expected output shapes.

Option B: Call Scan directly with curl
--------------------------------------
If you need to call Scan directly (e.g. from CI), this is the equivalent of what the scripts do.

1) Build the URL
- `BASE="https://${SCAN_HOST}:${SCAN_PORT}${SCAN_PREFIX}"`

2) Ensure TLS SNI/Host are correct while connecting to `SCAN_IP`
- Use curl `--resolve`:
  - `--resolve "${SCAN_HOST}:${SCAN_PORT}:${SCAN_IP}"`

3) Call endpoints

Common endpoints (with sample responses)
----------------------------------------

### Health/status

Request:
- `curl -sS --resolve "${SCAN_HOST}:${SCAN_PORT}:${SCAN_IP}" "${BASE}/status"`

Sample response shape:
```json
{
  "status": "OK"
}
```

### Scan discovery

Request:
- `curl -sS --resolve "${SCAN_HOST}:${SCAN_PORT}:${SCAN_IP}" "${BASE}/v0/scans"`

Sample response shape:
```json
{
  "scans": [
    {
      "scan_id": "...",
      "scan_host": "..."
    }
  ]
}
```

### Bulk Data: updates (event stream)

Request (first page):
- `curl -sS --resolve "${SCAN_HOST}:${SCAN_PORT}:${SCAN_IP}" \
  -H 'Content-Type: application/json' \
  -d '{"page_size":100,"daml_value_encoding":"compact_json"}' \
  "${BASE}/v2/updates"`

Request (next page, cursor-based):
- `curl -sS --resolve "${SCAN_HOST}:${SCAN_PORT}:${SCAN_IP}" \
  -H 'Content-Type: application/json' \
  -d '{"after":{"after_migration_id":3,"after_record_time":"2100-01-01T00:00:00Z"},"page_size":100,"daml_value_encoding":"compact_json"}' \
  "${BASE}/v2/updates"`

Sample response shape:
```json
{
  "transactions": [
    {
      "update_id": "...",
      "migration_id": 4,
      "record_time": "2026-01-25T16:41:02.076393Z",
      "events_by_id": {
        "...:0": {
          "event_type": "created_event",
          "template_id": "...:Splice.Amulet:Amulet",
          "contract_id": "...",
          "signatories": ["..."],
          "observers": ["..."]
        }
      }
    }
  ]
}
```

### Aggregates: holdings summary (balance-like view)

This is the preferred Scan-native way to get balance/fee totals for a party.

Request:
- `curl -sS --resolve "${SCAN_HOST}:${SCAN_PORT}:${SCAN_IP}" \
  -H 'Content-Type: application/json' \
  -d '{"party_ids":["<partyId>"]}' \
  "${BASE}/v0/holdings/summary"`

Sample response shape:
```json
{
  "items": [
    {
      "party_id": "<partyId>",
      "total_unlocked_coin": "0.0000000000",
      "total_locked_coin": "0.0000000000",
      "total_coin_holdings": "0.0000000000",
      "accumulated_holding_fees_unlocked": "0.0000000000",
      "accumulated_holding_fees_locked": "0.0000000000",
      "accumulated_holding_fees_total": "0.0000000000",
      "total_available_coin": "0.0000000000",
      "computed_as_of_round": 0
    }
  ]
}
```

### Network operations: open + issuing mining rounds

Request:
- `curl -sS --resolve "${SCAN_HOST}:${SCAN_PORT}:${SCAN_IP}" \
  -H 'Content-Type: application/json' \
  -d '{}' \
  "${BASE}/v0/open-and-issuing-mining-rounds"`

Sample response shape:
```json
{
  "open_mining_rounds": [],
  "issuing_mining_rounds": []
}
```

### Traffic status

Request:
- `curl -sS --resolve "${SCAN_HOST}:${SCAN_PORT}:${SCAN_IP}" \
  "${BASE}/v0/domains/<domain_id>/members/<member_id>/traffic-status"`

Sample response shape:
```json
{
  "actual": { "total_consumed": 0, "total_limit": 0 },
  "target": { "total_consumed": 0, "total_limit": 0 }
}
```
