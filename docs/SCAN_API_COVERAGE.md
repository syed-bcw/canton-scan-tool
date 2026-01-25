Scan API coverage tracker
========================

Purpose
-------
This file tracks which Scan endpoints we support with:
- Shell scripts under `api/scan/**` (runnable via `./run_api.sh`)
- Optional docs/examples

Scope rules
-----------
- Prefer `external` + `common` endpoints from the Scan OpenAPI reference.
- Avoid promoting `internal` endpoints unless explicitly requested.
- Avoid `deprecated` endpoints (only note them as “do not use”).

How to use
----------
- List scripts: `./run_api.sh list`
- Run one: `./run_api.sh run scan.v0.scans`

Coverage checklist (external)
-----------------------------

Connectivity / discovery
- [x] `GET /v0/scans` → api/scan/v0/scans.sh
- [x] `GET /v0/dso-sequencers` → api/scan/v0/dso_sequencers.sh
- [x] `GET /v0/admin/validator/licenses` → api/scan/v0/admin_validator_licenses.sh
- [x] `GET /v0/domains/{domain_id}/parties/{party_id}/participant-id` → api/scan/v0/domains_party_participant_id.sh

Operations
- [x] `GET /v0/dso` → api/scan/v0/dso.sh
- [x] `GET /v0/dso-party-id` → api/scan/v0/dso_party_id.sh
- [x] `GET /v0/validators/validator-faucets` → api/scan/v0/validators_validator_faucets.sh

Current state
- [x] `GET /v0/domains/{domain_id}/members/{member_id}/traffic-status` → api/scan/v0/domains_member_traffic_status.sh
- [x] `POST /v0/open-and-issuing-mining-rounds` → api/scan/v0/open_and_issuing_mining_rounds.sh
- [x] `GET /v0/closed-rounds` → api/scan/v0/closed_rounds.sh

Aggregates
- [x] `POST /v0/holdings/summary` → api/scan/v0/holdings_summary.sh
- [x] `POST /v0/holdings/state` → api/scan/v0/holdings_state.sh
- [x] `GET /v0/ans-entries` → api/scan/v0/ans_entries.sh
- [x] `GET /v0/ans-entries/by-party/{party}` → api/scan/v0/ans_entries_by_party.sh
- [x] `GET /v0/ans-entries/by-name/{name}` → api/scan/v0/ans_entries_by_name.sh

Bulk data
- [x] `POST /v2/updates` → api/scan/v2/updates.sh
- [x] `GET /v2/updates/{update_id}` → (existing) api/scan/v2/updates_tx.sh
- [x] `POST /v0/events` → api/scan/v0/events.sh
- [x] `GET /v0/events/{update_id}` → api/scan/v0/events_by_update_id.sh

ACS snapshots
- [x] `GET /v0/state/acs/snapshot-timestamp` → api/scan/v0/state_acs_snapshot_timestamp.sh
- [x] `GET /v0/state/acs/snapshot-timestamp-after` → api/scan/v0/state_acs_snapshot_timestamp_after.sh
- [x] `POST /v0/state/acs` → api/scan/v0/state_acs.sh

Coverage checklist (common)
---------------------------
- [x] `GET /status` → api/scan/common/status.sh
- [x] `GET /readyz` → api/scan/common/readyz.sh
- [x] `GET /livez` → api/scan/common/livez.sh
- [x] `GET /version` → api/scan/common/version.sh

Out of scope (by default)
-------------------------
- `internal` endpoints in the Scan OpenAPI reference (can be added if you want them as part of SaaS).
- `deprecated` endpoints (we should not build against them unless you explicitly want backward compatibility scripts).
