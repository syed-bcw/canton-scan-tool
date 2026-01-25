import { scanGetJson, scanPostJson, type ScanConfig } from "./scanClient";

export type HoldingsSummaryItem = {
  party_id: string;
  total_unlocked_coin: string;
  total_locked_coin: string;
  total_coin_holdings: string;
  accumulated_holding_fees_unlocked: string;
  accumulated_holding_fees_locked: string;
  accumulated_holding_fees_total: string;
  total_available_coin: string;
  computed_as_of_round?: number;
};

export type HoldingsSummaryResponse = {
  // Scan responses have used both keys over time; tolerate either.
  summaries?: HoldingsSummaryItem[];
  items?: HoldingsSummaryItem[];
  computed_as_of_round?: number;
  record_time?: string;
  migration_id?: number;
};

async function detectMigrationId(cfg: ScanConfig): Promise<number> {
  try {
    const dso = (await scanGetJson<any>(cfg, "/v0/dso-sequencers")) as any;
    const mid = dso?.domainSequencers?.[0]?.sequencers?.[0]?.migrationId;
    if (typeof mid === "number" && Number.isFinite(mid)) return mid;
    if (typeof mid === "string" && mid.trim() && Number.isFinite(Number(mid))) return Number(mid);
  } catch {
    // ignore
  }

  try {
    const updates = await scanPostJson<any>(cfg, "/v2/updates", {
      page_size: 1,
      daml_value_encoding: "compact_json",
    });
    const mid = updates?.transactions?.[0]?.migration_id;
    if (typeof mid === "number" && Number.isFinite(mid)) return mid;
    if (typeof mid === "string" && mid.trim() && Number.isFinite(Number(mid))) return Number(mid);
  } catch {
    // ignore
  }

  throw new Error("Could not determine migration_id; pass --migration-id or set MIGRATION_ID");
}

async function detectRecordTime(cfg: ScanConfig, migrationId: number, before: string): Promise<string> {
  const path = `/v0/state/acs/snapshot-timestamp?before=${encodeURIComponent(before)}&migration_id=${encodeURIComponent(
    String(migrationId)
  )}`;
  const resp = (await scanGetJson<any>(cfg, path)) as any;
  const rt = resp?.record_time;
  if (typeof rt === "string" && rt.trim()) return rt;
  throw new Error("Could not determine record_time; pass --record-time or set RECORD_TIME");
}

export async function fetchHoldingsSummary(
  cfg: ScanConfig,
  opts: {
    ownerPartyIds: string[];
    asOfRound?: number;
    migrationId?: number;
    recordTime?: string;
    recordTimeMatch?: string;
    before?: string;
  }
): Promise<HoldingsSummaryResponse> {
  if (!opts.ownerPartyIds.length) throw new Error("ownerPartyIds is required");

  const migrationId = opts.migrationId ?? (await detectMigrationId(cfg));
  const before = opts.before ?? new Date().toISOString();
  const recordTime = opts.recordTime ?? (await detectRecordTime(cfg, migrationId, before));
  const recordTimeMatch = opts.recordTimeMatch ?? "exact";

  const payload: Record<string, unknown> = {
    migration_id: migrationId,
    record_time: recordTime,
    record_time_match: recordTimeMatch,
    owner_party_ids: opts.ownerPartyIds,
  };

  if (opts.asOfRound !== undefined) {
    payload.as_of_round = opts.asOfRound;
  }

  return scanPostJson<HoldingsSummaryResponse>(cfg, "/v0/holdings/summary", payload);
}
