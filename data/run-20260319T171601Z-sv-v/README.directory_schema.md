# Directory Schema (per-validator Scan + Validator captures)

This run captures Scan API data split into:

## 1) Global (not validator-specific)
`data/run-<RUN_ID>/sv/global/`

Contains:
- discovery outputs (domain_id, migration_id, record_time, update_id, page(s) of `/v0/admin/validator/licenses`)
- `derived_params_global.txt`
- `acs_exact_record_time.txt` (if enabled)
- `scan.v2.updates.page1.json`

## 2) Per-validator captures
`data/run-<RUN_ID>/sv/validators/<validator_slug>/`

`<validator_slug>` is derived from `validator_party_id` by replacing non `[A-Za-z0-9._-]` with `_`.

Each validator folder contains two namespaces:
- `sv/` for Scan API data specific to that validator party/participant
- `v/` for conventional validator wallet API data (best effort, keyed by derived validator name)
- `validator_meta.txt` for mapping + capture metadata

### `sv/` contents
- `validator_meta.txt`
  - `validator_party_id=...`
  - `participant_id=...` (from `/v0/domains/{domain_id}/parties/{party}/participant-id`)
  - `domain_id=...`
  - `migration_id=...`
- `scan.v0.domains_party_participant_id.json`
- `scan.v0.validators_validator_faucets.json` (liveness for that single validator party id)
- `scan.v0.domains_member_traffic_status.json` (traffic status for that participant)
- `scan.v0.holdings_summary.json` (owned by that validator party id)
- `scan.v0.holdings_state.json` (only if `INCLUDE_HOLDINGS_STATE=1`)
- `scan.v0.ans_entries_by_party.json` (lookup by party id)
- `scan.v0.ans_entries_by_name.json` (only if ANS entry exists; derived from `ans_entries_by_party`)
- `scan.v0.acs_snapshot_for_party.json` (only if `INCLUDE_ACS_SNAPSHOT_FOR_PARTY=1`)

### `v/` contents
- wallet API responses from `api/validator/v0/wallet/*.sh`, e.g.:
  - `validator.v0.wallet.balance.json`
  - `validator.v0.wallet.transactions.json`
  - `validator.v0.wallet.user_status.json`
  - `validator.v0.wallet.amulets.json`
  - etc.

## 3) Index for joining
`data/run-<RUN_ID>/sv/global/validators_index.jsonl`

Each line:
`validator_party_id|validator_slug|participant_id|conventional_validator_name`

run_id=20260319T171601Z-sv-v
max_validators=3
license_page_limit=50
include_holdings_state=0
include_acs_snapshot_for_party=0
include_conventional_validator_api=1
before_ts=2026-03-19T19:13:08Z
