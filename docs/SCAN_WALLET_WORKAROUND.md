Scan-Only Wallet Views
======================

Context
-------
You want a wallet-like view (balances and a transaction-like feed) but you only have **Scan** access.

Scan does not necessarily expose `Splice.Wallet.*` templates publicly. In practice, you build wallet-like views from:

- Scan aggregates for balances/fees
- Scan Bulk Data updates for a transaction/event stream

Balances (recommended)
----------------------
Use the native Scan aggregates endpoint:

- `POST /api/scan/v0/holdings/summary`

It returns per-party totals such as:
- `total_unlocked_coin`, `total_locked_coin`, `total_coin_holdings`
- `accumulated_holding_fees_unlocked`, `accumulated_holding_fees_locked`, `accumulated_holding_fees_total`
- `total_available_coin`

See [docs/SCAN_API_CALLING.md](SCAN_API_CALLING.md) for a curl example and a sample response.

Transaction/event stream (best-effort)
-------------------------------------
Scan `POST /v2/updates` returns pages of transactions (updates). Each transaction contains `events_by_id` where each event is either:

- `created_event`
  - `template_id` (e.g. `...:Splice.Amulet:Amulet`)
  - `contract_id`
  - `signatories[]`, `observers[]`
  - `create_arguments` (optional; depends on `daml_value_encoding`)

- `exercised_event`
  - `template_id`
  - `contract_id`
  - `choice` (e.g. `AmuletRules_Transfer`)
  - `acting_parties[]`
  - `choice_argument` (optional; depends on `daml_value_encoding`)

This repo’s CLI fetches pages from Scan and filters the events.

Important limitations
---------------------
- This is **not** a 1:1 replacement for a wallet-specific API.
- Scan-visible events are limited to what Scan exposes.
- You generally won’t get a ready-made “transaction row” with direction/balance. You get ledger events; you derive a view from them.

Key workaround strategy
-----------------------
### 1) Jump to the “newest” migration window
In practice, older migrations may not contain what you care about.

We used a cursor pattern:
- `--after-migration-id 3 --after-record-time '2100-01-01T00:00:00Z'`

This forces Scan to move into the newest migration segment (in our observed environment: migration `4`).

### 2) Discover wallet-ish activity via keyword search
Use `search-updates` to find relevant templates/choices without knowing exact template names upfront.

Examples:
- Find Arkhia activity:
  - `node dist/cli.js search-updates --needle Arkhia-Validator-1 --after-migration-id 3 --after-record-time '2100-01-01T00:00:00Z' --max-pages 50 --page-size 200 --progress`

- Find transfer factory choices (this now searches `choice` too):
  - `node dist/cli.js search-updates --needle TransferFactory_Transfer --after-migration-id 3 --after-record-time '2100-01-01T00:00:00Z' --max-pages 50 --page-size 200 --progress`

### 3) Extract “transfer-like” events for a validator
For Arkhia, we observed `Splice.AmuletRules:AmuletRules` exercised with choice `AmuletRules_Transfer`.

Run:
- `node dist/cli.js party-updates --party '<validatorParty>' --after-migration-id 3 --after-record-time '2100-01-01T00:00:00Z' --choice-contains Transfer --include-args --max-pages 50 --page-size 200`

Or using the built-in validator list:
- `node dist/cli.js party-updates --validator arkhia --after-migration-id 3 --after-record-time '2100-01-01T00:00:00Z' --choice-contains Transfer --include-args --max-pages 50 --page-size 200`

How to interpret `AmuletRules_Transfer`
--------------------------------------
When you include args (`--include-args`), the CLI includes the raw `choice_argument`. For `AmuletRules_Transfer`, the structure we observed looks like:

- `choice_argument.transfer.sender` (party)
- `choice_argument.transfer.provider` (party)
- `choice_argument.transfer.inputs[]` (a list of tagged input references; includes contract ids)
- `choice_argument.transfer.outputs[]`
- `choice_argument.transfer.beneficiaries` (nullable)

This is enough to build a basic “transactions-like” feed:
- who initiated (`sender`)
- whose validator is providing (`provider`)
- what contracts were consumed as inputs
- which round/context it applied to (in `choice_argument.context`, when present)

Other transfer-like patterns
----------------------------
We also observed transfer-like activity via:
- `Splice.ExternalPartyAmuletRules:ExternalPartyAmuletRules` with choice `TransferFactory_Transfer`

Even if Scan doesn’t expose `Splice.Wallet.*`, these Amulet/Transfer events can still provide a useful proxy.

Suggested next step
-------------------
If you want, we can add a dedicated command that outputs a normalized “transfer row” (JSONL) for a validator:
- timestamps, sender/provider, choice, contract ids, and selected context fields.
