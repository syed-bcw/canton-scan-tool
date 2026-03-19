# Directory Schema (per-validator Scan captures)

This run captures Scan API data split into:

## 1) Global (not validator-specific)
`data/run-20260319T171601Z-v3-acs/sv/global/`

Contains discovery outputs such as:
- `scan.v0.scans.json`
- `scan.v0.dso_sequencers.json`
- `scan.v0.state_acs_snapshot_timestamp.json`
- `scan.v2.updates.page1.json`
- admin license discovery pages under `scan.v0.admin_validator_licenses.page*.json`
- `derived_params_global.txt`

## 2) Per-validator captures
`data/run-20260319T171601Z-v3-acs/sv/validators/<validator_slug>/`

`<validator_slug>` is derived from `validator_party_id` by replacing non `[A-Za-z0-9._-]` with `_`.

Each validator folder contains:
- `validator_meta.txt`:
  - `validator_party_id=...`
  - `participant_id=...` (from `/v0/domains/{domain_id}/parties/{party}/participant-id`)
  - `domain_id=...`
  - `migration_id=...`
- `scan.v0.domains_party_participant_id.json`
- `scan.v0.validators_validator_faucets.json`
- `scan.v0.domains_member_traffic_status.json`
- `scan.v0.holdings_summary.json`
- `scan.v0.ans_entries_by_party.json`
- `scan.v0.acs_snapshot_for_party.json` (because `INCLUDE_ACS_SNAPSHOT_FOR_PARTY=1`)

## 3) Index for joining
`data/run-20260319T171601Z-v3-acs/sv/global/validators_index.jsonl`

Each line:
`validator_party_id|validator_slug|participant_id`

