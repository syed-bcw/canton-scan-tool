# Notes / Action Items

## What we learned from `validator_license_out.json`

This file is useful even in Scan-only setups because the payload contains network party IDs.

- Response shape (observed):
  - `validator_licenses[]`: array of license contracts
  - `validator_licenses[].payload.validator`: party id (e.g. `FNA-validator-1::...`)
  - `validator_licenses[].payload.sponsor`: sponsor party id
  - `validator_licenses[].payload.dso`: DSO party id (often constant)
  - `next_page_token`: integer token for pagination

## Scan-only equivalents

If you want wallet-like views but only have Scan access:

- Balances + fees (recommended): use Scan aggregates
  - `POST /api/scan/v0/holdings/summary`
- Transaction/event stream: use Bulk Data updates
  - `POST /api/scan/v2/updates`

See also:
- [docs/SCAN_API_CALLING.md](../docs/SCAN_API_CALLING.md)
- [docs/SCAN_WALLET_WORKAROUND.md](../docs/SCAN_WALLET_WORKAROUND.md)
