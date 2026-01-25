import { scanPostJson, type ScanConfig } from "./scanClient";
import type { ScanUpdatesRequest, ScanUpdatesResponse, ScanEvent } from "./partyUpdates";

export type WalletBalance = {
  round: number | null;
  effective_unlocked_qty: string | null;
  effective_locked_qty: string | null;
  total_holding_fees: string | null;
  meta: {
    pages_fetched: number;
    transactions_scanned: number;
    active_amulets: number;
    active_locked_amulets: number;
    as_of_round_source: "arg" | "derived" | "unknown";
  };
};

type AmuletAmount = {
  initialAmount: string;
  createdAt: { number: string };
  ratePerRound: { rate: string };
};

type ActiveAmulet = {
  kind: "Amulet" | "LockedAmulet";
  contract_id: string;
  owner: string;
  amount: AmuletAmount;
};

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function getString(value: unknown, key: string): string | undefined {
  if (!isRecord(value)) return undefined;
  const v = value[key];
  return typeof v === "string" ? v : undefined;
}

function getObject(value: unknown, key: string): Record<string, unknown> | undefined {
  if (!isRecord(value)) return undefined;
  const v = value[key];
  return isRecord(v) ? v : undefined;
}

function parseAmountFromArgs(kind: "Amulet" | "LockedAmulet", args: unknown): { owner: string; amount: AmuletAmount } | null {
  // Amulet: { owner, amount: { initialAmount, createdAt: {number}, ratePerRound: {rate} } }
  // LockedAmulet: { amulet: { owner, amount: {...} }, lock: {...} }
  const root = isRecord(args) ? args : null;
  if (!root) return null;

  const payload = kind === "Amulet" ? root : getObject(root, "amulet");
  if (!payload) return null;

  const owner = getString(payload, "owner");
  const amountObj = getObject(payload, "amount");
  if (!owner || !amountObj) return null;

  const initialAmount = getString(amountObj, "initialAmount");
  const createdAtObj = getObject(amountObj, "createdAt");
  const createdAtNumber = createdAtObj ? getString(createdAtObj, "number") : undefined;
  const ratePerRoundObj = getObject(amountObj, "ratePerRound");
  const rate = ratePerRoundObj ? getString(ratePerRoundObj, "rate") : undefined;

  if (!initialAmount || !createdAtNumber || !rate) return null;

  return {
    owner,
    amount: {
      initialAmount,
      createdAt: { number: createdAtNumber },
      ratePerRound: { rate },
    },
  };
}

const SCALE = 10n;
const SCALE_FACTOR = 10n ** SCALE;

function parseDecimalToScaledInt(value: string): bigint {
  // Parses decimal strings like "132096.4906520218" into a BigInt scaled by 1e10.
  // Truncates extra decimals beyond 10 (Scan amounts appear to use 10).
  const m = value.trim().match(/^(-?)(\d+)(?:\.(\d+))?$/);
  if (!m) throw new Error(`Invalid decimal: ${value}`);
  const sign = m[1] === "-" ? -1n : 1n;
  const whole = BigInt(m[2]);
  const fracRaw = (m[3] ?? "").slice(0, Number(SCALE));
  const fracPadded = fracRaw.padEnd(Number(SCALE), "0");
  const frac = fracPadded.length ? BigInt(fracPadded) : 0n;
  return sign * (whole * SCALE_FACTOR + frac);
}

function scaledIntToDecimal(value: bigint): string {
  const sign = value < 0n ? "-" : "";
  const abs = value < 0n ? -value : value;
  const whole = abs / SCALE_FACTOR;
  const frac = abs % SCALE_FACTOR;
  const fracStr = frac.toString().padStart(Number(SCALE), "0");
  return `${sign}${whole.toString()}.${fracStr}`;
}

function clampMin0(v: bigint): bigint {
  return v < 0n ? 0n : v;
}

function computeEffective(amount: AmuletAmount, asOfRound: number): { effective: bigint; fees: bigint } {
  const createdAt = Number(amount.createdAt.number);
  const roundsElapsed = Math.max(0, asOfRound - createdAt);
  const initial = parseDecimalToScaledInt(amount.initialAmount);
  const rate = parseDecimalToScaledInt(amount.ratePerRound.rate);

  const fees = BigInt(roundsElapsed) * rate;
  const effective = clampMin0(initial - fees);
  return { effective, fees };
}

function templateEntity(templateId: string): string | undefined {
  const parts = templateId.split(":");
  if (parts.length < 3) return undefined;
  return parts[2];
}

export async function computeWalletBalanceFromScan(
  cfg: ScanConfig,
  opts: {
    party: string;
    pageSize: number;
    maxPages: number;
    damlValueEncoding?: string;
    afterMigrationId?: number;
    afterRecordTime?: string;
    asOfRound?: number;
    onProgress?: (s: { pages_fetched: number; transactions_scanned: number; active_contracts: number; last_cursor?: any }) => void;
  }
): Promise<WalletBalance> {
  let afterMigrationId = opts.afterMigrationId;
  let afterRecordTime = opts.afterRecordTime;

  const active = new Map<string, ActiveAmulet>();
  let maxCreatedAtRound: number | undefined;

  let pagesFetched = 0;
  let txScanned = 0;

  for (let page = 0; page < opts.maxPages; page++) {
    const req: ScanUpdatesRequest = {
      page_size: opts.pageSize,
      daml_value_encoding: opts.damlValueEncoding ?? "compact_json",
    };

    if (afterMigrationId !== undefined || afterRecordTime !== undefined) {
      if (afterMigrationId === undefined || afterRecordTime === undefined) {
        throw new Error("Both afterMigrationId and afterRecordTime must be set together");
      }
      req.after = {
        after_migration_id: afterMigrationId,
        after_record_time: afterRecordTime,
      };
    }

    const resp = await scanPostJson<ScanUpdatesResponse>(cfg, "/v2/updates", req);
    if (!resp.transactions || resp.transactions.length === 0) break;

    pagesFetched++;
    txScanned += resp.transactions.length;

    for (const tx of resp.transactions) {
      for (const ev of Object.values(tx.events_by_id ?? {})) {
        const entity = templateEntity(ev.template_id);

        if (ev.event_type === "created_event") {
          if (entity !== "Amulet" && entity !== "LockedAmulet") continue;

          const parsed = parseAmountFromArgs(entity, ev.create_arguments);
          if (!parsed) continue;

          const createdAt = Number(parsed.amount.createdAt.number);
          if (Number.isFinite(createdAt)) {
            maxCreatedAtRound = maxCreatedAtRound === undefined ? createdAt : Math.max(maxCreatedAtRound, createdAt);
          }

          active.set(ev.contract_id, {
            kind: entity,
            contract_id: ev.contract_id,
            owner: parsed.owner,
            amount: parsed.amount,
          });
        } else if (ev.event_type === "exercised_event") {
          // Best-effort: consuming exercise archives the target contract.
          if (ev.consuming) {
            if (active.has(ev.contract_id)) active.delete(ev.contract_id);
          }
        }
      }
    }

    const last = resp.transactions[resp.transactions.length - 1];
    afterMigrationId = last.migration_id;
    afterRecordTime = last.record_time;

    opts.onProgress?.({
      pages_fetched: pagesFetched,
      transactions_scanned: txScanned,
      active_contracts: active.size,
      last_cursor: { migration_id: afterMigrationId, record_time: afterRecordTime },
    });
  }

  let asOfRoundSource: WalletBalance["meta"]["as_of_round_source"] = "unknown";
  let asOfRound: number | undefined = opts.asOfRound;
  if (asOfRound !== undefined) {
    asOfRoundSource = "arg";
  } else if (maxCreatedAtRound !== undefined) {
    asOfRound = maxCreatedAtRound;
    asOfRoundSource = "derived";
  }

  let unlockedEffective = 0n;
  let lockedEffective = 0n;
  let holdingFees = 0n;

  let activeAmulets = 0;
  let activeLocked = 0;

  for (const c of active.values()) {
    if (c.owner !== opts.party) continue;

    if (c.kind === "Amulet") activeAmulets++;
    if (c.kind === "LockedAmulet") activeLocked++;

    if (asOfRound === undefined) continue;

    const { effective, fees } = computeEffective(c.amount, asOfRound);
    holdingFees += fees;

    if (c.kind === "Amulet") unlockedEffective += effective;
    else lockedEffective += effective;
  }

  return {
    round: asOfRound ?? null,
    effective_unlocked_qty: asOfRound !== undefined ? scaledIntToDecimal(unlockedEffective) : null,
    effective_locked_qty: asOfRound !== undefined ? scaledIntToDecimal(lockedEffective) : null,
    total_holding_fees: asOfRound !== undefined ? scaledIntToDecimal(holdingFees) : null,
    meta: {
      pages_fetched: pagesFetched,
      transactions_scanned: txScanned,
      active_amulets: activeAmulets,
      active_locked_amulets: activeLocked,
      as_of_round_source: asOfRoundSource,
    },
  };
}
