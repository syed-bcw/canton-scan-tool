import { scanPostJson, type ScanConfig } from "./scanClient";

export type HoldingsSummaryItem = {
  party_id: string;
  total_unlocked_coin: string;
  total_locked_coin: string;
  total_coin_holdings: string;
  accumulated_holding_fees_unlocked: string;
  accumulated_holding_fees_locked: string;
  accumulated_holding_fees_total: string;
  total_available_coin: string;
  computed_as_of_round: number;
};

export type HoldingsSummaryResponse = {
  items: HoldingsSummaryItem[];
};

export async function fetchHoldingsSummary(
  cfg: ScanConfig,
  opts: { partyIds: string[]; asOfRound?: number }
): Promise<HoldingsSummaryResponse> {
  if (!opts.partyIds.length) throw new Error("partyIds is required");

  const payload: Record<string, unknown> = {
    party_ids: opts.partyIds,
  };

  if (opts.asOfRound !== undefined) {
    payload.as_of_round = opts.asOfRound;
  }

  return scanPostJson<HoldingsSummaryResponse>(cfg, "/v0/holdings/summary", payload);
}
