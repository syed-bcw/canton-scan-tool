# Mapping: Postman "wallet transactions" vs Scan-derived output

This doc compares:
- **Postman** output from a wallet-transactions API capture (file: `postman get transactions out`)
- **Our Scan-only Node CLI** output from `POST /v2/updates` (event-level JSONL)

## Quick snapshots

### Postman wallet-transactions capture (from `postman get transactions out`)
Observed facts from the file:
- `.items | length` = **1000**
- Top-level keys per item:
  - `transaction_type`, `transaction_subtype`, `event_id`, `date`, `provider`, `sender`, `receivers`,
    `holding_fees`, `amulet_price`, `app_rewards_used`, `validator_rewards_used`, `sv_rewards_used`,
    `transfer_instruction_receiver`, `transfer_instruction_amount`, `transfer_instruction_cid`, `description`
- `transaction_subtype` keys: `template_id`, `choice`, `amulet_operation`, `interface_id`
- Distinct values in this capture:
  - `transaction_subtype.choice`: **1** (`WalletAppInstall_ExecuteBatch`)
  - `transaction_subtype.template_id`: **1** (`…:Splice.Wallet.Install:WalletAppInstall`)

Example (first item, selected fields):
```json
{
  "transaction_type": "transfer",
  "transaction_subtype": {
    "template_id": "…:Splice.Wallet.Install:WalletAppInstall",
    "choice": "WalletAppInstall_ExecuteBatch"
  },
  "event_id": "#1220966a…:1",
  "date": "2026-01-25T16:41:02.076393Z",
  "provider": "Arkhia-Validator-1::…",
  "sender": { "party": "Arkhia-Validator-1::…", "amount": "21.2661332039" },
  "receivers": [],
  "holding_fees": "0.0000000000",
  "amulet_price": "0.1571090000",
  "validator_rewards_used": "21.2661332039"
}
```

### Scan-only Node CLI (event-level JSONL)
Our Scan path is **not** `/wallet/transactions`. We query Scan via `POST /v2/updates` and emit **ledger events**.

Example (one JSONL line produced by `search-updates --needle AmuletRules_Transfer`):
```json
{
  "update_id": "1220ae18…",
  "migration_id": 4,
  "record_time": "2025-12-10T16:23:27.663342Z",
  "event_id": "1220ae18…:0",
  "event_type": "exercised_event",
  "template_id": "…:Splice.AmuletRules:AmuletRules",
  "package_name": "splice-amulet",
  "choice": "AmuletRules_Transfer",
  "acting_parties": ["Digital-Asset-2::…"],
  "choice_argument": { "transfer": { "sender": "…", "provider": "…" } },
  "matched_by": ["choice"]
}
```

## What we can and cannot map

### What we *have achieved*
- We can reliably connect to Scan via localhost port-forward **while keeping TLS SNI/Host correct**.
- We can pull **event-level history** from Scan (`/v2/updates`) and filter by:
  - party involvement
  - template prefix
  - choice equals / contains
  - keyword search across template/package/choice/args
- We can extract **transfer-like ledger activity** (e.g., `AmuletRules_Transfer`) as a best-effort “wallet-ish feed”.

### What we *cannot reproduce from Scan* (in current observations)
- The Postman capture is entirely `Splice.Wallet.Install:WalletAppInstall` / `WalletAppInstall_ExecuteBatch`.
- Probing Scan with `search-updates --needle WalletAppInstall` across thousands of events returned **0 matches**.
  - This strongly suggests those wallet templates are **not visible via Scan `/v2/updates`** (at least in the scanned window / visibility constraints).

## Field mapping (best-effort)

Postman fields are already *normalized/aggregated* into a transaction object. Scan gives lower-level ledger events.

| Postman field | Meaning (from output) | Scan event source (best-effort) | Status |
|---|---|---|---|
| `event_id` | Identifies the event driving the transaction | Scan `event_id` | Partial (formats differ) |
| `date` | Transaction timestamp | Scan `record_time` | Partial (semantics differ) |
| `provider` | Provider party for the transaction | Sometimes in `choice_argument.transfer.provider` | Partial (only if present) |
| `sender.party` | Sender party | `choice_argument.transfer.sender` (if present) | Partial |
| `sender.amount` | Amount moved | Often inside `choice_argument.transfer` (structure varies by template) | Partial |
| `receivers[]` | Receiver parties + amounts | Often inside `choice_argument.transfer.outputs` or similar | Partial |
| `transaction_subtype.template_id` | Wallet template that produced the tx | Scan `template_id` (but wallet template not visible) | Not achievable for wallet install tx |
| `transaction_subtype.choice` | Wallet choice that produced the tx | Scan `choice` | Not achievable for wallet install tx |
| `holding_fees` | Fees charged | Might be derivable if present in args/events | Usually missing |
| `amulet_price` | Price at time | Might be derivable if present in args/events | Usually missing |
| `*_rewards_used` | Reward accounting | Might be derivable if present in args/events | Usually missing |
| `transfer_instruction_*` | Optional transfer instruction metadata | Might exist in other templates | Unknown |

## Recommendation: closest Scan-only equivalent

If the goal is a *transaction-like feed* using only Scan:
- Use Scan `/v2/updates` and extract a canonical subset from `exercised_event` choices like `AmuletRules_Transfer`.
- Treat it as **event stream**, not a perfect `/wallet/transactions` clone.

Practical command:
- `node dist/cli.js search-updates --needle AmuletRules_Transfer --after-migration-id 3 --after-record-time '2100-01-01T00:00:00Z' --max-pages 10 --page-size 200 --include-args --progress`

## Next steps (if you want closer parity)
1. Confirm what `/wallet/transactions` endpoint is returning (validator API version, params, auth scope).
2. Decide the **minimum required fields** (e.g., sender, receiver, amount, timestamp).
3. Implement a “normalizer” command that converts Scan event JSONL into a transaction JSON schema.
   - This will still be approximate, but it will be stable and easy to consume.

## Related: balance

We added a **best-effort Scan-derived balance** command:

- `node dist/cli.js wallet-balance --party '<partyId>' --after-migration-id 3 --after-record-time '2100-01-01T00:00:00Z' --max-pages 50 --page-size 200 --progress`

Notes:
- This computes balances from Scan-visible contracts like `Splice.Amulet:Amulet` and `Splice.Amulet:LockedAmulet`.
- It is not guaranteed to match any wallet-specific balance API, because that can depend on wallet-only templates and server-side aggregation not exposed via Scan.

Preferred approach for balances/fees:
- Use Scan aggregates `POST /api/scan/v0/holdings/summary` (see [docs/SCAN_API_CALLING.md](SCAN_API_CALLING.md)).
