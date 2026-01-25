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
