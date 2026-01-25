Scan API endpoint reference
===========================

This document describes every Scan API endpoint we currently call in this repo, how to call it, what it’s for, and the expected response shape.

Capabilities index (what you can offer)
--------------------------------------

| Capability | Best endpoint(s) | Script(s) |
|---|---|---|
| Monitoring / uptime | `GET /readyz`, `GET /livez`, `GET /status`, `GET /version` | `scan.common.readyz`, `scan.common.livez`, `scan.common.status`, `scan.common.version` |
| Scan discovery | `GET /v0/scans` | `scan.v0.scans` |
| Sequencer inventory | `GET /v0/dso-sequencers` | `scan.v0.dso_sequencers` |
| Validator inventory | `GET /v0/admin/validator/licenses` | `scan.v0.admin_validator_licenses` (see also flows) |
| Validator liveness | `GET /v0/validators/validator-faucets` | `scan.v0.validators_validator_faucets` |
| Network ops snapshot | `GET /v0/dso`, `GET /v0/dso-party-id` | `scan.v0.dso`, `scan.v0.dso_party_id` |
| Party hosting lookup | `GET /v0/domains/{domain_id}/parties/{party_id}/participant-id` | `scan.v0.domains_party_participant_id` |
| Traffic credits | `GET /v0/domains/{domain_id}/members/{member_id}/traffic-status` | `scan.v0.domains_member_traffic_status` |
| Mining rounds status | `POST /v0/open-and-issuing-mining-rounds`, `GET /v0/closed-rounds` | `scan.v0.open_and_issuing_mining_rounds`, `scan.v0.closed_rounds` |
| Wallet-like balance | `POST /v0/holdings/summary` | `scan.v0.holdings_summary` (also available via the Node/TS CLI) |
| Holdings detail | `POST /v0/holdings/state` | `scan.v0.holdings_state` |
| Name directory (ANS) | `GET /v0/ans-entries*` | `scan.v0.ans_entries`, `scan.v0.ans_entries_by_party`, `scan.v0.ans_entries_by_name` |
| Raw ledger history stream | `POST /v2/updates`, `GET /v2/updates/{update_id}` | `scan.v2.updates`, `scan.v2.updates_tx` |
| Explorer timeline (with verdict when available) | `POST /v0/events`, `GET /v0/events/{update_id}` | `scan.v0.events`, `scan.v0.events_by_update_id` |
| Consistent snapshot reads (ACS) | `GET /v0/state/acs/snapshot-timestamp*`, `POST /v0/state/acs` | `scan.v0.state_acs_snapshot_timestamp`, `scan.v0.state_acs_snapshot_timestamp_after`, `scan.v0.state_acs` |

Notes:
- Some scripts require `jq` (URL encoding, JSON payload building).
- For exact inputs/expected outputs, jump to the endpoint section below.

This repo is Scan-only
----------------------
- All examples assume Scan is reachable under `SCAN_PREFIX` (default `/api/scan`).
- No kubectl instructions and no JWT/auth guidance are included here.

Connection settings (shared)
----------------------------
These environment variables are used by both shell scripts and the Node/TS CLI:

- `SCAN_SCHEME` (default `https`)
- `SCAN_HOST` (TLS SNI hostname + HTTP Host header)
- `SCAN_PORT` (default `3128`)
- `SCAN_IP` (where to connect, often `127.0.0.1` when using a local proxy)
- `SCAN_PREFIX` (default `/api/scan`)

Convenience variables for curl:

- `BASE="${SCAN_SCHEME}://${SCAN_HOST}:${SCAN_PORT}${SCAN_PREFIX}"`
- `RESOLVE="--resolve ${SCAN_HOST}:${SCAN_PORT}:${SCAN_IP}"`

Using scripts vs curl
---------------------
- Script runner: `./run_api.sh run <name>`
- Direct curl: equivalent request shown in each endpoint section.

Unless stated otherwise:
- Requests use `Accept: application/json`.
- POST requests use `Content-Type: application/json`.

Common (monitoring)
-------------------

### GET /status
Purpose:
- Lightweight “is the HTTP service up” status (implementation-specific, but generally stable).

Script:
- `./run_api.sh run scan.common.status`

Curl:
- `curl -sS ${RESOLVE} "${BASE}/status"`

Expected response shape:
```json
{ "success": { "id": "...", "uptime": "...", "active": true } }
```
(Exact fields may vary by deployment.)

### GET /readyz
Purpose:
- Readiness probe for monitoring / load balancers.

Script:
- `./run_api.sh run scan.common.readyz`

Curl:
- `curl -sS ${RESOLVE} "${BASE}/readyz"`

Expected response:
- `200 OK` when ready; `503` when not ready.

### GET /livez
Purpose:
- Liveness probe for monitoring / orchestrators.

Script:
- `./run_api.sh run scan.common.livez`

Curl:
- `curl -sS ${RESOLVE} "${BASE}/livez"`

Expected response:
- `200 OK` when live; `503` when not live.

### GET /version
Purpose:
- Returns build/version metadata (useful for debugging rollouts).

Script:
- `./run_api.sh run scan.common.version`

Curl:
- `curl -sS ${RESOLVE} "${BASE}/version"`

Expected response shape:
```json
{ "version": "0.5.x", "commit_ts": "2025-12-02T16:56:35Z" }
```

External (Scan)
---------------

### GET /v0/scans
Purpose:
- Discover Scan public URLs grouped by synchronizer (`domainId`).

Script:
- `./run_api.sh run scan.v0.scans`

Curl:
- `curl -sS ${RESOLVE} "${BASE}/v0/scans"`

Expected response shape:
```json
{ "scans": [ { "domainId": "...", "scans": [ { "publicUrl": "...", "svName": "..." } ] } ] }
```

### GET /v0/dso-sequencers
Purpose:
- Discover sequencer configuration per synchronizer (`domainId`).

Script:
- `./run_api.sh run scan.v0.dso_sequencers`

Curl:
- `curl -sS ${RESOLVE} "${BASE}/v0/dso-sequencers"`

Expected response shape:
```json
{ "domainSequencers": [ { "domainId": "...", "sequencers": [ { "migrationId": 1, "id": "...", "url": "...", "svName": "..." } ] } ] }
```

### GET /v0/admin/validator/licenses
Purpose:
- Lists validators approved by the DSO (paged newest-first). Useful for “who’s onboarded” inventory.

Script:
- `./run_api.sh run scan.v0.admin_validator_licenses`

Inputs:
- Optional `AFTER` (pagination token)
- Optional `LIMIT`

Curl:
- First page: `curl -sS ${RESOLVE} "${BASE}/v0/admin/validator/licenses"`
- With paging: `curl -sS ${RESOLVE} "${BASE}/v0/admin/validator/licenses?after=123&limit=100"`

Expected response shape:
```json
{ "validator_licenses": [ { "template_id": "...", "contract_id": "...", "payload": {} } ], "next_page_token": 123 }
```

### GET /v0/domains/{domain_id}/parties/{party_id}/participant-id
Purpose:
- Resolves which participant hosts a given party on a given synchronizer.

Script:
- `./run_api.sh run scan.v0.domains_party_participant_id -- <domain_id> <party_id>`

Curl:
- `curl -sS ${RESOLVE} "${BASE}/v0/domains/<domain_id>/parties/<party_id>/participant-id"`

Expected response shape:
```json
{ "participant_id": "..." }
```

### GET /v0/validators/validator-faucets?validator_ids=...
Purpose:
- Validator liveness stats (how many rounds a validator collected faucets, etc.).

Script:
- `VALIDATOR_IDS='p1,p2' ./run_api.sh run scan.v0.validators_validator_faucets`

Curl:
- `curl -sS ${RESOLVE} "${BASE}/v0/validators/validator-faucets?validator_ids=p1&validator_ids=p2"`

Expected response shape:
```json
{ "validatorsReceivedFaucets": [ { "validator": "...", "numRoundsCollected": 1, "lastCollectedInRound": 1 } ] }
```

### GET /v0/dso-party-id
Purpose:
- Returns the DSO party id for the connected network.

Script:
- `./run_api.sh run scan.v0.dso_party_id`

Curl:
- `curl -sS ${RESOLVE} "${BASE}/v0/dso-party-id"`

Expected response shape:
```json
{ "dso_party_id": "..." }
```

### GET /v0/dso
Purpose:
- Returns key on-ledger operational contracts (rules, latest mining round, etc.). Useful for dashboards.

Script:
- `./run_api.sh run scan.v0.dso`

Curl:
- `curl -sS ${RESOLVE} "${BASE}/v0/dso"`

Expected response shape (high-level):
```json
{ "dso_party_id": "...", "latest_mining_round": {"contract": {"contract_id":"..."}}, "amulet_rules": {"contract": {"contract_id":"..."}} }
```

### GET /v0/domains/{domain_id}/members/{member_id}/traffic-status
Purpose:
- Traffic credits/consumption status for a participant or mediator on a synchronizer.

Script:
- `DOMAIN_ID='...' MEMBER_ID='PAR::...::...' ./run_api.sh run scan.v0.domains_member_traffic_status`

Curl:
- `curl -sS ${RESOLVE} "${BASE}/v0/domains/<domain_id>/members/<member_id>/traffic-status"`

Expected response shape:
```json
{ "traffic_status": { "actual": {"total_consumed": 0, "total_limit": 0}, "target": {"total_purchased": 0} } }
```

### POST /v0/open-and-issuing-mining-rounds
Purpose:
- Lists open + issuing mining rounds. Supports client-side caching by re-sending returned contract IDs.

Script:
- `./run_api.sh run scan.v0.open_and_issuing_mining_rounds`
- Optional: `PAYLOAD='{ "cached_open_mining_round_contract_ids": ["..."], "cached_issuing_round_contract_ids": ["..."] }'`

Curl:
- `curl -sS ${RESOLVE} -H 'Content-Type: application/json' -d '{}' "${BASE}/v0/open-and-issuing-mining-rounds"`

Expected response shape:
```json
{ "time_to_live_in_microseconds": 1, "open_mining_rounds": {}, "issuing_mining_rounds": {} }
```

### GET /v0/closed-rounds
Purpose:
- Returns closed rounds still in post-close processing (often empty, but useful for operational monitoring).

Script:
- `./run_api.sh run scan.v0.closed_rounds`

Curl:
- `curl -sS ${RESOLVE} "${BASE}/v0/closed-rounds"`

Expected response shape:
```json
{ "rounds": [ { "contract_id": "...", "payload": {} } ] }
```

Aggregates (holdings + ANS)
---------------------------

### POST /v0/holdings/summary
Purpose:
- “Balance-like” aggregate for one or more parties (fast, preferred for wallet-like totals).

Script:
- `PARTY_ID='...' ./run_api.sh run scan.v0.holdings_summary`
- Optional: `AS_OF_ROUND=123`
- Or fully custom payload: `PAYLOAD='{"party_ids":["..."],"as_of_round":123}'`

Curl:
- `curl -sS ${RESOLVE} -H 'Content-Type: application/json' -d '{"party_ids":["<party>"],"as_of_round":123}' "${BASE}/v0/holdings/summary"`

Expected response shape:
```json
{ "summaries": [ { "party_id": "...", "total_available_coin": "...", "total_coin_holdings": "..." } ], "computed_as_of_round": 123 }
```

### POST /v0/holdings/state
Purpose:
- Paginated detailed holdings events (used when you need underlying contracts, not just totals).

Script:
- `PARTY_ID='...' PAGE_SIZE=100 ./run_api.sh run scan.v0.holdings_state`
- Or custom payload: `PAYLOAD='{"party_ids":["..."],"page_size":100}'`

Curl:
- `curl -sS ${RESOLVE} -H 'Content-Type: application/json' -d '{"party_ids":["<party>"],"page_size":100}' "${BASE}/v0/holdings/state"`

Expected response shape:
```json
{ "created_events": [ { "contract_id": "...", "template_id": "...", "create_arguments": {} } ], "next_page_token": 1 }
```

### GET /v0/ans-entries
Purpose:
- Lists ANS entries filtered by name prefix (directory/search experience).

Script:
- `./run_api.sh run scan.v0.ans_entries -- 50 alice`
  - arg1: `PAGE_SIZE` (default 50)
  - arg2: `NAME_PREFIX` (optional)

Curl:
- `curl -sS ${RESOLVE} "${BASE}/v0/ans-entries?page_size=50&name_prefix=alice"`

Expected response shape:
```json
{ "entries": [ { "contract_id": "...", "user": "...", "name": "...", "url": "...", "expires_at": "..." } ] }
```

### GET /v0/ans-entries/by-party/{party}
Purpose:
- Lookup the first ANS entry for a user party.

Script:
- `./run_api.sh run scan.v0.ans_entries_by_party -- <party>`

Curl:
- `curl -sS ${RESOLVE} "${BASE}/v0/ans-entries/by-party/<party>"`

Expected response shape:
```json
{ "entry": { "contract_id": "...", "user": "...", "name": "...", "expires_at": "..." } }
```

### GET /v0/ans-entries/by-name/{name}
Purpose:
- Lookup an ANS entry by exact name.

Script:
- `./run_api.sh run scan.v0.ans_entries_by_name -- <name>`

Curl:
- `curl -sS ${RESOLVE} "${BASE}/v0/ans-entries/by-name/<name>"`

Expected response shape:
```json
{ "entry": { "contract_id": "...", "user": "...", "name": "...", "expires_at": "..." } }
```

Bulk data (history)
-------------------

### POST /v2/updates
Purpose:
- Paged raw update history stream (transactions + reassignment events). Use for analytics / indexing.

Script:
- `./run_api.sh run scan.v2.updates`

Inputs (env):
- `PAGE_SIZE=100`
- `DAML_VALUE_ENCODING=compact_json`
- Optional cursor: `AFTER_MIGRATION_ID=... AFTER_RECORD_TIME='...'`

Curl:
- First page:
  - `curl -sS ${RESOLVE} -H 'Content-Type: application/json' -d '{"page_size":100,"daml_value_encoding":"compact_json"}' "${BASE}/v2/updates"`

Expected response shape:
```json
{ "transactions": [ { "update_id": "...", "migration_id": 1, "record_time": "...", "events_by_id": {} } ] }
```

### GET /v2/updates/{update_id}
Purpose:
- Fetch a single update by id (debugging, deep links).

Script:
- `./run_api.sh run scan.v2.updates_tx -- <update_id>`

Curl:
- `curl -sS ${RESOLVE} "${BASE}/v2/updates/<update_id>"`

Expected response shape:
```json
{ "update_id": "...", "migration_id": 1, "record_time": "...", "root_event_ids": ["..."], "events_by_id": {} }
```

### POST /v0/events
Purpose:
- Paged “event” history that can include mediator verdicts (when available). Good for explorer-grade timelines.

Script:
- `./run_api.sh run scan.v0.events`

Inputs (env):
- `PAGE_SIZE=100`
- `DAML_VALUE_ENCODING=compact_json`
- Optional cursor: `AFTER_MIGRATION_ID=... AFTER_RECORD_TIME='...'`

Curl:
- `curl -sS ${RESOLVE} -H 'Content-Type: application/json' -d '{"page_size":100,"daml_value_encoding":"compact_json"}' "${BASE}/v0/events"`

Expected response shape:
```json
{ "events": [ { "update": { "update_id": "...", "record_time": "..." }, "verdict": { "verdict_result": "..." } } ] }
```

### GET /v0/events/{update_id}
Purpose:
- Fetch a single event by update id.

Script:
- `./run_api.sh run scan.v0.events_by_update_id -- <update_id>`

Curl:
- `curl -sS ${RESOLVE} "${BASE}/v0/events/<update_id>"`

Expected response shape:
```json
{ "update": { "update_id": "..." }, "verdict": { "verdict_result": "..." } }
```

ACS snapshots
-------------

### GET /v0/state/acs/snapshot-timestamp
Purpose:
- Find the record time of the most recent ACS snapshot before a given timestamp (for consistent queries).

Script:
- `./run_api.sh run scan.v0.state_acs_snapshot_timestamp -- "2026-01-25T00:00:00Z" 1`

Curl:
- `curl -sS ${RESOLVE} "${BASE}/v0/state/acs/snapshot-timestamp?before=2026-01-25T00%3A00%3A00Z&migration_id=1"`

Expected response shape:
```json
{ "record_time": "2026-01-22T16:45:12.328396" }
```

### GET /v0/state/acs/snapshot-timestamp-after
Purpose:
- Find the first snapshot after a given timestamp (useful for forward navigation).

Script:
- `./run_api.sh run scan.v0.state_acs_snapshot_timestamp_after -- "2026-01-25T00:00:00Z" 1`

Curl:
- `curl -sS ${RESOLVE} "${BASE}/v0/state/acs/snapshot-timestamp-after?after=2026-01-25T00%3A00%3A00Z&migration_id=1"`

Expected response shape:
```json
{ "record_time": "2026-01-25T00:00:00.000000Z" }
```

### POST /v0/state/acs
Purpose:
- Retrieve ACS snapshot contents (paged) for a given migration id and record time.

Script:
- Required:
  - `MIGRATION_ID=1 RECORD_TIME='2026-01-22T16:45:12.328396' ./run_api.sh run scan.v0.state_acs`
- Optional filters:
  - `PARTY_IDS='p1,p2'` and/or `TEMPLATES='pkg:Module:Template'`
  - `AFTER=123 PAGE_SIZE=200`

Curl:
- `curl -sS ${RESOLVE} -H 'Content-Type: application/json' -d '{"migration_id":1,"record_time":"...","record_time_match":"exact","page_size":100}' "${BASE}/v0/state/acs"`

Expected response shape:
```json
{ "record_time": "...", "migration_id": 1, "created_events": [ { "contract_id": "...", "template_id": "...", "create_arguments": {} } ], "next_page_token": 1 }
```

Flows (composed scripts)
------------------------
These are multi-step helpers that call multiple Scan endpoints and process JSON.

### flows.scan_participant_ids_for_validators
Purpose:
- Takes a validator license JSON response and resolves participant IDs for each validator party.

Run:
- `./run_api.sh run flows.scan_participant_ids_for_validators -- validator_license_out.json`

Output:
- JSON Lines (one object per validator) with keys:
  - `domain_id`, `validator_party_id`, `participant_id` OR `error` + `response`

Notes / gotchas
---------------
- Some scripts require `jq` for URL encoding and JSON building.
- `scan.common.*` endpoints may be routed differently in some deployments; if so, override `SCAN_PREFIX` accordingly.
