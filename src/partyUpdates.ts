import { scanPostJson, type ScanConfig } from "./scanClient";

export type ScanUpdatesRequest = {
  page_size: number;
  daml_value_encoding?: string;
  after?: {
    after_migration_id: number;
    after_record_time: string;
  };
};

export type ScanUpdatesResponse = {
  transactions: Array<{
    update_id: string;
    migration_id: number;
    workflow_id?: string;
    record_time: string;
    effective_at?: string;
    synchronizer_id?: string;
    root_event_ids: string[];
    events_by_id: Record<string, ScanEvent>;
  }>;
};

export type ScanEvent =
  | {
      event_type: "created_event";
      event_id: string;
      contract_id: string;
      template_id: string;
      package_name?: string;
      create_arguments?: unknown;
      signatories?: string[];
      observers?: string[];
    }
  | {
      event_type: "exercised_event";
      event_id: string;
      contract_id: string;
      template_id: string;
      package_name?: string;
      choice?: string;
      choice_argument?: unknown;
      acting_parties?: string[];
      consuming?: boolean;
      interface_id?: string | null;
    };

export type NormalizedPartyEvent = {
  update_id: string;
  migration_id: number;
  record_time: string;
  event_id: string;
  event_type: string;
  template_id: string;
  template_module?: string;
  template_entity?: string;
  package_name?: string;
  contract_id: string;
  choice?: string;
  consuming?: boolean;
  signatories?: string[];
  observers?: string[];
  acting_parties?: string[];
  create_arguments?: unknown;
  choice_argument?: unknown;
};

export type SearchMatchEvent = NormalizedPartyEvent & {
  matched_by: string[];
};

export type PartyScanStats = {
  pages_fetched: number;
  transactions_scanned: number;
  events_matched: number;
  last_cursor?: {
    migration_id: number;
    record_time: string;
  };
};

export type TopPartiesStats = {
  pages_fetched: number;
  transactions_scanned: number;
  events_scanned: number;
  unique_parties: number;
  last_cursor?: {
    migration_id: number;
    record_time: string;
  };
};

export function parseTemplateId(templateId: string): { template_module?: string; template_entity?: string } {
  // Typical format: <packageIdHash>:<Module>:<Entity>
  const parts = templateId.split(":");
  if (parts.length < 3) return {};
  return {
    template_module: parts[1],
    template_entity: parts[2],
  };
}

function partyInvolvesEvent(party: string, ev: ScanEvent): boolean {
  const candidates: Array<string | undefined> = [];

  if (ev.event_type === "created_event") {
    for (const p of ev.signatories ?? []) candidates.push(p);
    for (const p of ev.observers ?? []) candidates.push(p);
  } else {
    for (const p of ev.acting_parties ?? []) candidates.push(p);
  }

  return candidates.includes(party);
}

function partiesFromEvent(ev: ScanEvent): string[] {
  const out: string[] = [];
  if (ev.event_type === "created_event") {
    for (const p of ev.signatories ?? []) out.push(p);
    for (const p of ev.observers ?? []) out.push(p);
  } else {
    for (const p of ev.acting_parties ?? []) out.push(p);
  }
  return out;
}

function containsString(value: unknown, needle: string, depth = 0, substring = false): boolean {
  if (depth > 8) return false;
  if (value === null || value === undefined) return false;
  if (typeof value === "string") return substring ? value.includes(needle) : value === needle;
  if (typeof value === "number" || typeof value === "boolean") return false;
  if (Array.isArray(value)) return value.some((v) => containsString(v, needle, depth + 1, substring));
  if (typeof value === "object") {
    for (const v of Object.values(value as Record<string, unknown>)) {
      if (containsString(v, needle, depth + 1, substring)) return true;
    }
  }
  return false;
}

function partyMentionedInArguments(party: string, ev: ScanEvent, substring: boolean): boolean {
  if (ev.event_type === "created_event") return containsString(ev.create_arguments, party, 0, substring);
  return containsString(ev.choice_argument, party, 0, substring);
}

function templateMatchesPrefix(ev: ScanEvent, templatePrefix?: string): boolean {
  if (!templatePrefix) return true;
  const { template_module } = parseTemplateId(ev.template_id);
  if (!template_module) return false;
  return template_module.startsWith(templatePrefix);
}

export async function fetchTopParties(
  cfg: ScanConfig,
  opts: {
    pageSize: number;
    maxPages: number;
    topN: number;
    templatePrefix?: string;
    damlValueEncoding?: string;
    afterMigrationId?: number;
    afterRecordTime?: string;
    onProgress?: (stats: TopPartiesStats) => void;
  }
): Promise<Array<{ party: string; count: number }>> {
  let afterMigrationId = opts.afterMigrationId;
  let afterRecordTime = opts.afterRecordTime;

  const counts = new Map<string, number>();
  const stats: TopPartiesStats = {
    pages_fetched: 0,
    transactions_scanned: 0,
    events_scanned: 0,
    unique_parties: 0,
  };

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

    stats.pages_fetched++;
    stats.transactions_scanned += resp.transactions.length;

    for (const tx of resp.transactions) {
      for (const ev of Object.values(tx.events_by_id ?? {})) {
        stats.events_scanned++;
        if (!templateMatchesPrefix(ev, opts.templatePrefix)) continue;
        for (const party of partiesFromEvent(ev)) {
          counts.set(party, (counts.get(party) ?? 0) + 1);
        }
      }
    }

    const last = resp.transactions[resp.transactions.length - 1];
    afterMigrationId = last.migration_id;
    afterRecordTime = last.record_time;

    stats.last_cursor = {
      migration_id: afterMigrationId,
      record_time: afterRecordTime,
    };
    stats.unique_parties = counts.size;

    opts.onProgress?.(stats);
  }

  const sorted = Array.from(counts.entries())
    .map(([party, count]) => ({ party, count }))
    .sort((a, b) => b.count - a.count);

  return sorted.slice(0, Math.max(0, opts.topN));
}

export type SearchScanStats = {
  pages_fetched: number;
  transactions_scanned: number;
  events_scanned: number;
  events_matched: number;
  last_cursor?: {
    migration_id: number;
    record_time: string;
  };
};

export async function searchUpdates(
  cfg: ScanConfig,
  opts: {
    needle: string;
    pageSize: number;
    maxPages: number;
    damlValueEncoding?: string;
    afterMigrationId?: number;
    afterRecordTime?: string;
    includeTemplateId?: boolean;
    includePackageName?: boolean;
    includeArguments?: boolean;
    includeChoice?: boolean;
    includeArgs?: boolean;
    onProgress?: (stats: SearchScanStats) => void;
  }
): Promise<SearchMatchEvent[]> {
  let afterMigrationId = opts.afterMigrationId;
  let afterRecordTime = opts.afterRecordTime;

  const out: SearchMatchEvent[] = [];
  const stats: SearchScanStats = {
    pages_fetched: 0,
    transactions_scanned: 0,
    events_scanned: 0,
    events_matched: 0,
  };

  const includeTemplateId = opts.includeTemplateId ?? true;
  const includePackageName = opts.includePackageName ?? true;
  const includeArguments = opts.includeArguments ?? true;
  const includeChoice = opts.includeChoice ?? true;

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

    stats.pages_fetched++;
    stats.transactions_scanned += resp.transactions.length;

    for (const tx of resp.transactions) {
      for (const ev of Object.values(tx.events_by_id ?? {})) {
        stats.events_scanned++;

        const matched_by: string[] = [];

        if (includeTemplateId && ev.template_id?.includes(opts.needle)) matched_by.push("template_id");
        if (includePackageName && ev.package_name?.includes(opts.needle)) matched_by.push("package_name");

        if (includeChoice && ev.event_type === "exercised_event" && ev.choice?.includes(opts.needle)) {
          matched_by.push("choice");
        }

        if (includeArguments) {
          const inArgs = partyMentionedInArguments(opts.needle, ev, true);
          if (inArgs) matched_by.push("arguments");
        }

        if (matched_by.length === 0) continue;

        const { template_module, template_entity } = parseTemplateId(ev.template_id);

        out.push({
          update_id: tx.update_id,
          migration_id: tx.migration_id,
          record_time: tx.record_time,
          event_id: ev.event_id,
          event_type: ev.event_type,
          template_id: ev.template_id,
          template_module,
          template_entity,
          package_name: ev.package_name,
          contract_id: ev.contract_id,
          choice: ev.event_type === "exercised_event" ? ev.choice : undefined,
          consuming: ev.event_type === "exercised_event" ? ev.consuming : undefined,
          signatories: ev.event_type === "created_event" ? ev.signatories : undefined,
          observers: ev.event_type === "created_event" ? ev.observers : undefined,
          acting_parties: ev.event_type === "exercised_event" ? ev.acting_parties : undefined,
          create_arguments: opts.includeArgs && ev.event_type === "created_event" ? ev.create_arguments : undefined,
          choice_argument: opts.includeArgs && ev.event_type === "exercised_event" ? ev.choice_argument : undefined,
          matched_by,
        });

        stats.events_matched++;
      }
    }

    const last = resp.transactions[resp.transactions.length - 1];
    afterMigrationId = last.migration_id;
    afterRecordTime = last.record_time;
    stats.last_cursor = { migration_id: afterMigrationId, record_time: afterRecordTime };

    opts.onProgress?.(stats);
  }

  return out;
}

export async function fetchPartyEvents(
  cfg: ScanConfig,
  opts: {
    party: string;
    pageSize: number;
    maxPages: number;
    templatePrefix?: string;
    choiceEquals?: string;
    choiceContains?: string;
    damlValueEncoding?: string;
    afterMigrationId?: number;
    afterRecordTime?: string;
    onProgress?: (stats: PartyScanStats) => void;
    matchInArgs?: boolean;
    matchSubstringInArgs?: boolean;
    includeArgs?: boolean;
  }
): Promise<NormalizedPartyEvent[]> {
  let afterMigrationId = opts.afterMigrationId;
  let afterRecordTime = opts.afterRecordTime;

  const out: NormalizedPartyEvent[] = [];
  const stats: PartyScanStats = {
    pages_fetched: 0,
    transactions_scanned: 0,
    events_matched: 0,
  };

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

    stats.pages_fetched++;
    stats.transactions_scanned += resp.transactions.length;

    for (const tx of resp.transactions) {
      for (const ev of Object.values(tx.events_by_id ?? {})) {
        const matches = partyInvolvesEvent(opts.party, ev);
        const mentions =
          opts.matchInArgs && partyMentionedInArguments(opts.party, ev, Boolean(opts.matchSubstringInArgs));

        if (!matches && !mentions) {
          continue;
        }
        if (!templateMatchesPrefix(ev, opts.templatePrefix)) continue;

        if (opts.choiceEquals || opts.choiceContains) {
          const choice = ev.event_type === "exercised_event" ? ev.choice : undefined;
          if (!choice) continue;
          if (opts.choiceEquals && choice !== opts.choiceEquals) continue;
          if (opts.choiceContains && !choice.includes(opts.choiceContains)) continue;
        }

        const { template_module, template_entity } = parseTemplateId(ev.template_id);

        out.push({
          update_id: tx.update_id,
          migration_id: tx.migration_id,
          record_time: tx.record_time,
          event_id: ev.event_id,
          event_type: ev.event_type,
          template_id: ev.template_id,
          template_module,
          template_entity,
          package_name: ev.package_name,
          contract_id: ev.contract_id,
          choice: ev.event_type === "exercised_event" ? ev.choice : undefined,
          consuming: ev.event_type === "exercised_event" ? ev.consuming : undefined,
          signatories: ev.event_type === "created_event" ? ev.signatories : undefined,
          observers: ev.event_type === "created_event" ? ev.observers : undefined,
          acting_parties: ev.event_type === "exercised_event" ? ev.acting_parties : undefined,
          create_arguments: opts.includeArgs && ev.event_type === "created_event" ? ev.create_arguments : undefined,
          choice_argument: opts.includeArgs && ev.event_type === "exercised_event" ? ev.choice_argument : undefined,
        });

        stats.events_matched++;
      }
    }

    const last = resp.transactions[resp.transactions.length - 1];
    afterMigrationId = last.migration_id;
    afterRecordTime = last.record_time;

    stats.last_cursor = {
      migration_id: afterMigrationId,
      record_time: afterRecordTime,
    };

    opts.onProgress?.(stats);
  }

  return out;
}
