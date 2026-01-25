Canton Scan Tools
=================

This repo contains:
- a lightweight shell "API collection" under `api/**` (run via `./run_api.sh`)
- a Node.js + TypeScript CLI for Scan-only workflows (this README)

Prereqs
- Node.js 18+ (you have Node 20)
- Network access to a Scan API endpoint (direct, or via any local TCP proxy)

Install
- `npm install`

Build
- `npm run build`

CLI
- Dev (no build): `npm run dev -- <command> [options]`
- Built: `node dist/cli.js <command> [options]`

Docs
- Scan API calling guide (curl + scripts): [docs/SCAN_API_CALLING.md](docs/SCAN_API_CALLING.md)
- Scan-only wallet workaround: [docs/SCAN_WALLET_WORKAROUND.md](docs/SCAN_WALLET_WORKAROUND.md)
- Postman vs Scan mapping: [docs/POSTMAN_WALLET_TRANSACTIONS_MAPPING.md](docs/POSTMAN_WALLET_TRANSACTIONS_MAPPING.md)

Common env vars (match the shell scripts)
- `SCAN_HOST` (default `scan.sv-1.global.canton.network.sync.global`)
- `SCAN_PORT` (default `3128`)
- `SCAN_IP` (default `127.0.0.1`) — where to connect (e.g. a local proxy IP)
- `SCAN_PREFIX` (default `/api/scan`)

Commands

1) Filter Scan updates by party
- `node dist/cli.js party-updates --party '<partyId>' --max-pages 10 --page-size 100`
- Optional: `--template-prefix 'Splice.Wallet'`
- Optional (probing): `--match-in-args` (and `--match-substring-in-args`) to also match party IDs that appear inside event arguments
- Optional: `--choice <name>` or `--choice-contains <text>` (only exercised events)
- Optional: `--include-args` to include raw arguments for matched events

Outputs JSONL (one event per line) so you can pipe to `jq`:
- `... | jq -r '.template_id' | sort | uniq -c`

2) Wallet template probe (best-effort)
- `node dist/cli.js wallet-transactions --party '<partyId>'`

Note: this is not a 1:1 replacement for any wallet-specific API. It only finds ledger events visible in Scan that involve your party.

2b) Wallet balance (best-effort, Scan-derived)

This approximates a wallet balance using Scan-visible contracts (notably `Splice.Amulet:Amulet` and `Splice.Amulet:LockedAmulet`).

Prefer the native Scan aggregates endpoint for balances and fees:
- `POST /api/scan/v0/holdings/summary` (see [docs/SCAN_API_CALLING.md](docs/SCAN_API_CALLING.md))

Or via CLI (native aggregates):
- `node dist/cli.js holdings-summary --party '<partyId>'`
- Optional: `node dist/cli.js holdings-summary --party '<partyId>' --as-of-round <n>`

- `node dist/cli.js wallet-balance --party '<partyId>' --after-migration-id 3 --after-record-time '2100-01-01T00:00:00Z' --max-pages 50 --page-size 200 --progress`

Tip: if you already know the desired round number, pass `--as-of-round <n>` for stable results.

3) Find high-occurrence parties (to pick a good probe target)
- `node dist/cli.js top-parties --max-pages 5 --page-size 200`
- Filter to a module prefix: `node dist/cli.js top-parties --template-prefix Splice.DSO --max-pages 20`

4) Second-attempt workaround: keyword search over all updates
- Find anything wallet-ish (template/package/args): `node dist/cli.js search-updates --needle Wallet --max-pages 50 --page-size 200 --progress`
- Include args in results: add `--include-args`
- Find Arkhia mentions by short name (even if full party ID isn't present): `node dist/cli.js search-updates --needle Arkhia-Validator-1 --max-pages 50 --page-size 200 --progress`
- Jump to newest migration first: add `--after-migration-id 3 --after-record-time '2100-01-01T00:00:00Z'`

Example: extract transfer-like events for a party (no Splice.Wallet needed)
- `node dist/cli.js party-updates --party '<partyId>' --after-migration-id 3 --after-record-time '2100-01-01T00:00:00Z' --choice-contains Transfer --include-args --max-pages 50 --page-size 200`

Scripts

List validators from a license dump (like your `jq ... | sort | uniq | head` pipeline):
- `./scripts/list_validators_from_license.sh validator_license_out.json 30`

Interactive: pick a validator from the license dump and write matched events to `out/*.jsonl`:
- `./scripts/select_validator_and_scan.sh validator_license_out.json out`

Tuning knobs (env vars):
- `AFTER_MIGRATION_ID=3 AFTER_RECORD_TIME='2100-01-01T00:00:00Z' MAX_PAGES=50 PAGE_SIZE=200 CHOICE_CONTAINS=Transfer ./scripts/select_validator_and_scan.sh ...`
