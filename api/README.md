API collection (shell)
======================

This directory holds shell scripts that call your APIs (a lightweight Postman-style collection).

Organization
- Place scripts under `api/...` with `.sh` extension (e.g. `api/scan/v0/scans.sh`).

Runner
- Use the top-level `run_api.sh` to discover and run scripts.

Usage
- `./run_api.sh list` — list all scripts with index and name
- `./run_api.sh run <index|name> [-- extra args]` — run a specific script, forwarding extra args
- `./run_api.sh all [-- extra args]` — run all scripts in order

Names
- Script names are derived from their path under `api/` by replacing `/` with `.` and removing `.sh`.
  Example: `api/scan/v0/scans.sh` → `scan.v0.scans`

Notes
- Scripts are executed with their existing executable bit, or via `sh` if not executable.
- Keep scripts simple and idempotent; runner runs scripts sequentially.

Shared config
- You can create a `.env` file in the repo root (next to `run_api.sh`) to share settings.
  `run_api.sh` will source it automatically.

Helper library
- Prefer using `api/_lib/http.sh` from scripts so URL / `--resolve` / headers stay consistent.
- Common Scan env vars (override as needed):
  - `SCAN_SCHEME` (default `https`)
  - `SCAN_HOST` (default `scan.sv-1.global.canton.network.sync.global`)
  - `SCAN_PORT` (default `3128`)
  - `SCAN_IP` (default `127.0.0.1`)
  - `SCAN_PREFIX` (default `/api/scan`)
- Common flags:
  - `API_VERBOSE=1` to add curl `-v`
  - `API_CURL_EXTRA="..."` to append extra curl args

Flows
- `api/flows/*.sh` scripts can chain multiple calls and may rely on `jq` or `python3` for JSON parsing.
