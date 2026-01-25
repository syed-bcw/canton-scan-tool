#!/usr/bin/env node

import { Command } from "commander";
import { getDefaultScanConfig } from "./scanClient";
import { fetchPartyEvents, fetchTopParties, searchUpdates } from "./partyUpdates";
import { fetchHoldingsSummary } from "./holdingsSummary";
import { computeWalletBalanceFromScan } from "./walletBalance";
import { KNOWN_VALIDATORS, resolveValidatorParty } from "./validators";

process.stdout.on("error", (err: any) => {
  if (err?.code === "EPIPE") process.exit(0);
  throw err;
});

const program = new Command();

program
  .name("canton-scan")
  .description("Scan-only CLI helpers (port-forward compatible)")
  .version("0.0.0");

program
  .command("validators")
  .description("List known validators from the local config")
  .action(() => {
    process.stdout.write(JSON.stringify(KNOWN_VALIDATORS, null, 2));
    process.stdout.write("\n");
  });

function resolvePartyFromOpts(opts: any): string {
  const party = opts.party as string | undefined;
  const validatorKey = opts.validator as string | undefined;

  if (party && validatorKey) {
    throw new Error("Provide only one of --party or --validator");
  }
  if (party) return party;
  if (validatorKey) return resolveValidatorParty(validatorKey);

  throw new Error("Missing party selector: provide --party <partyId> or --validator <key>");
}

program
  .command("party-updates")
  .description("Fetch /v2/updates pages and output events involving a party (JSONL)")
  .option("--party <partyId>", "Party ID to filter on")
  .option("--validator <key>", "Known validator key (see: canton-scan validators)")
  .option("--template-prefix <prefix>", "Filter by template module prefix (e.g. Splice.Wallet)")
  .option("--choice <name>", "Only include exercised_event with this exact choice")
  .option("--choice-contains <text>", "Only include exercised_event whose choice contains this substring")
  .option("--page-size <n>", "Scan /v2/updates page_size", "100")
  .option("--max-pages <n>", "Max pages to fetch", "5")
  .option("--after-migration-id <n>", "Start after migration id")
  .option("--after-record-time <iso>", "Start after record time (RFC3339/ISO-8601)")
  .option("--daml-value-encoding <enc>", "DAML value encoding", "compact_json")
  .option("--progress", "Print scan progress to stderr")
  .option(
    "--match-in-args",
    "also match if the party appears inside create_arguments/choice_argument (for probing; may include false positives)",
    false
  )
  .option(
    "--match-substring-in-args",
    "when --match-in-args is set, match party as a substring inside strings",
    false
  )
  .option("--include-args", "Include create_arguments/choice_argument in output", false)
  .action(async (opts) => {
    const cfg = getDefaultScanConfig(process.env);

    const partyId = resolvePartyFromOpts(opts);

    const pageSize = Number(opts.pageSize);
    const maxPages = Number(opts.maxPages);
    if (!Number.isFinite(pageSize) || pageSize <= 0) throw new Error("Invalid --page-size");
    if (!Number.isFinite(maxPages) || maxPages <= 0) throw new Error("Invalid --max-pages");

    const afterMigrationId = opts.afterMigrationId !== undefined ? Number(opts.afterMigrationId) : undefined;
    const afterRecordTime = opts.afterRecordTime as string | undefined;

    let lastProgressAt = 0;
    const onProgress = opts.progress
      ? (s: any) => {
          const now = Date.now();
          if (now - lastProgressAt < 500) return;
          lastProgressAt = now;
          const cursor = s.last_cursor ? ` cursor=(${s.last_cursor.migration_id}, ${s.last_cursor.record_time})` : "";
          process.stderr.write(
            `[party-updates] pages=${s.pages_fetched} tx=${s.transactions_scanned} matched=${s.events_matched}${cursor}\n`
          );
        }
      : undefined;

    const events = await fetchPartyEvents(cfg, {
      party: partyId,
      pageSize,
      maxPages,
      templatePrefix: opts.templatePrefix,
      choiceEquals: opts.choice,
      choiceContains: opts.choiceContains,
      damlValueEncoding: opts.damlValueEncoding,
      afterMigrationId,
      afterRecordTime,
      onProgress,
      matchInArgs: Boolean(opts.matchInArgs),
      matchSubstringInArgs: Boolean(opts.matchSubstringInArgs),
      includeArgs: Boolean(opts.includeArgs),
    });

    for (const e of events) {
      process.stdout.write(JSON.stringify(e));
      process.stdout.write("\n");
    }

    process.stderr.write(`[party-updates] done events=${events.length}\n`);
  });

program
  .command("top-parties")
  .description("Scan /v2/updates and print the most frequently seen parties")
  .option("--template-prefix <prefix>", "Only consider events whose template module starts with this prefix")
  .option("--page-size <n>", "Scan /v2/updates page_size", "200")
  .option("--max-pages <n>", "Max pages to fetch", "10")
  .option("--top <n>", "How many parties to print", "20")
  .option("--after-migration-id <n>", "Start after migration id")
  .option("--after-record-time <iso>", "Start after record time (RFC3339/ISO-8601)")
  .option("--daml-value-encoding <enc>", "DAML value encoding", "compact_json")
  .option("--progress", "Print scan progress to stderr")
  .action(async (opts) => {
    const cfg = getDefaultScanConfig(process.env);

    const pageSize = Number(opts.pageSize);
    const maxPages = Number(opts.maxPages);
    const topN = Number(opts.top);
    if (!Number.isFinite(pageSize) || pageSize <= 0) throw new Error("Invalid --page-size");
    if (!Number.isFinite(maxPages) || maxPages <= 0) throw new Error("Invalid --max-pages");
    if (!Number.isFinite(topN) || topN <= 0) throw new Error("Invalid --top");

    const afterMigrationId = opts.afterMigrationId !== undefined ? Number(opts.afterMigrationId) : undefined;
    const afterRecordTime = opts.afterRecordTime as string | undefined;

    let lastProgressAt = 0;
    const onProgress = opts.progress
      ? (s: any) => {
          const now = Date.now();
          if (now - lastProgressAt < 500) return;
          lastProgressAt = now;
          const cursor = s.last_cursor ? ` cursor=(${s.last_cursor.migration_id}, ${s.last_cursor.record_time})` : "";
          process.stderr.write(
            `[top-parties] pages=${s.pages_fetched} tx=${s.transactions_scanned} events=${s.events_scanned} parties=${s.unique_parties}${cursor}\n`
          );
        }
      : undefined;

    const parties = await fetchTopParties(cfg, {
      pageSize,
      maxPages,
      topN,
      templatePrefix: opts.templatePrefix,
      damlValueEncoding: opts.damlValueEncoding,
      afterMigrationId,
      afterRecordTime,
      onProgress,
    });

    process.stdout.write(JSON.stringify(parties, null, 2));
    process.stdout.write("\n");
  });

program
  .command("search-updates")
  .description("Scan /v2/updates and output events where a keyword appears (JSONL)")
  .requiredOption("--needle <text>", "Substring to search for")
  .option("--page-size <n>", "Scan /v2/updates page_size", "200")
  .option("--max-pages <n>", "Max pages to fetch", "20")
  .option("--after-migration-id <n>", "Start after migration id")
  .option("--after-record-time <iso>", "Start after record time (RFC3339/ISO-8601)")
  .option("--daml-value-encoding <enc>", "DAML value encoding", "compact_json")
  .option("--no-template-id", "Do not search template_id")
  .option("--no-package-name", "Do not search package_name")
  .option("--no-choice", "Do not search exercised_event choice")
  .option("--no-arguments", "Do not search create_arguments/choice_argument")
  .option("--include-args", "Include create_arguments/choice_argument in output", false)
  .option("--progress", "Print scan progress to stderr")
  .action(async (opts) => {
    const cfg = getDefaultScanConfig(process.env);

    const pageSize = Number(opts.pageSize);
    const maxPages = Number(opts.maxPages);
    if (!Number.isFinite(pageSize) || pageSize <= 0) throw new Error("Invalid --page-size");
    if (!Number.isFinite(maxPages) || maxPages <= 0) throw new Error("Invalid --max-pages");

    const afterMigrationId = opts.afterMigrationId !== undefined ? Number(opts.afterMigrationId) : undefined;
    const afterRecordTime = opts.afterRecordTime as string | undefined;

    let lastProgressAt = 0;
    const onProgress = opts.progress
      ? (s: any) => {
          const now = Date.now();
          if (now - lastProgressAt < 500) return;
          lastProgressAt = now;
          const cursor = s.last_cursor ? ` cursor=(${s.last_cursor.migration_id}, ${s.last_cursor.record_time})` : "";
          process.stderr.write(
            `[search-updates] pages=${s.pages_fetched} tx=${s.transactions_scanned} events=${s.events_scanned} matched=${s.events_matched}${cursor}\n`
          );
        }
      : undefined;

    const matches = await searchUpdates(cfg, {
      needle: String(opts.needle),
      pageSize,
      maxPages,
      damlValueEncoding: opts.damlValueEncoding,
      afterMigrationId,
      afterRecordTime,
      includeTemplateId: Boolean(opts.templateId),
      includePackageName: Boolean(opts.packageName),
      includeChoice: Boolean(opts.choice),
      includeArguments: Boolean(opts.arguments),
      includeArgs: Boolean(opts.includeArgs),
      onProgress,
    });

    for (const m of matches) {
      process.stdout.write(JSON.stringify(m));
      process.stdout.write("\n");
    }

    process.stderr.write(`[search-updates] done events=${matches.length}\n`);
  });

program
  .command("wallet-transactions")
  .description("Convenience wrapper: party-updates with template-prefix=Splice.Wallet")
  .option("--party <partyId>", "Party ID to filter on")
  .option("--validator <key>", "Known validator key (see: canton-scan validators)")
  .option("--page-size <n>", "Scan /v2/updates page_size", "100")
  .option("--max-pages <n>", "Max pages to fetch", "10")
  .option("--after-migration-id <n>", "Start after migration id")
  .option("--after-record-time <iso>", "Start after record time (RFC3339/ISO-8601)")
  .option("--daml-value-encoding <enc>", "DAML value encoding", "compact_json")
  .option("--progress", "Print scan progress to stderr")
  .option(
    "--match-in-args",
    "also match if the party appears inside create_arguments/choice_argument (for probing; may include false positives)",
    false
  )
  .option(
    "--match-substring-in-args",
    "when --match-in-args is set, match party as a substring inside strings",
    false
  )
  .option("--include-args", "Include create_arguments/choice_argument in output", false)
  .action(async (opts) => {
    const cfg = getDefaultScanConfig(process.env);

    const partyId = resolvePartyFromOpts(opts);

    const pageSize = Number(opts.pageSize);
    const maxPages = Number(opts.maxPages);
    const afterMigrationId = opts.afterMigrationId !== undefined ? Number(opts.afterMigrationId) : undefined;
    const afterRecordTime = opts.afterRecordTime as string | undefined;

    let lastProgressAt = 0;
    const onProgress = opts.progress
      ? (s: any) => {
          const now = Date.now();
          if (now - lastProgressAt < 500) return;
          lastProgressAt = now;
          const cursor = s.last_cursor ? ` cursor=(${s.last_cursor.migration_id}, ${s.last_cursor.record_time})` : "";
          process.stderr.write(
            `[wallet-transactions] pages=${s.pages_fetched} tx=${s.transactions_scanned} matched=${s.events_matched}${cursor}\n`
          );
        }
      : undefined;

    const events = await fetchPartyEvents(cfg, {
      party: partyId,
      pageSize,
      maxPages,
      templatePrefix: "Splice.Wallet",
      damlValueEncoding: opts.damlValueEncoding,
      afterMigrationId,
      afterRecordTime,
      onProgress,
      matchInArgs: Boolean(opts.matchInArgs),
      matchSubstringInArgs: Boolean(opts.matchSubstringInArgs),
      includeArgs: Boolean(opts.includeArgs),
    });

    for (const e of events) {
      process.stdout.write(JSON.stringify(e));
      process.stdout.write("\n");
    }

    process.stderr.write(`[wallet-transactions] done events=${events.length}\n`);
  });

program
  .command("wallet-balance")
  .description("Best-effort wallet balance derived from Scan-visible Amulet contracts")
  .option("--party <partyId>", "Party ID to compute balance for")
  .option("--validator <key>", "Known validator key (see: canton-scan validators)")
  .option("--page-size <n>", "Scan /v2/updates page_size", "200")
  .option("--max-pages <n>", "Max pages to fetch", "20")
  .option("--after-migration-id <n>", "Start after migration id")
  .option("--after-record-time <iso>", "Start after record time (RFC3339/ISO-8601)")
  .option("--daml-value-encoding <enc>", "DAML value encoding", "compact_json")
  .option(
    "--as-of-round <n>",
    "Compute effective amounts at this round number (defaults to max createdAt.number seen in the scanned window)"
  )
  .option("--progress", "Print scan progress to stderr")
  .action(async (opts) => {
    const cfg = getDefaultScanConfig(process.env);
    const partyId = resolvePartyFromOpts(opts);

    const pageSize = Number(opts.pageSize);
    const maxPages = Number(opts.maxPages);
    if (!Number.isFinite(pageSize) || pageSize <= 0) throw new Error("Invalid --page-size");
    if (!Number.isFinite(maxPages) || maxPages <= 0) throw new Error("Invalid --max-pages");

    const afterMigrationId = opts.afterMigrationId !== undefined ? Number(opts.afterMigrationId) : undefined;
    const afterRecordTime = opts.afterRecordTime as string | undefined;

    const asOfRound = opts.asOfRound !== undefined ? Number(opts.asOfRound) : undefined;
    if (asOfRound !== undefined && (!Number.isFinite(asOfRound) || asOfRound <= 0)) {
      throw new Error("Invalid --as-of-round");
    }

    let lastProgressAt = 0;
    const onProgress = opts.progress
      ? (s: any) => {
          const now = Date.now();
          if (now - lastProgressAt < 500) return;
          lastProgressAt = now;
          const cursor = s.last_cursor ? ` cursor=(${s.last_cursor.migration_id}, ${s.last_cursor.record_time})` : "";
          process.stderr.write(
            `[wallet-balance] pages=${s.pages_fetched} tx=${s.transactions_scanned} active=${s.active_contracts}${cursor}\n`
          );
        }
      : undefined;

    const bal = await computeWalletBalanceFromScan(cfg, {
      party: partyId,
      pageSize,
      maxPages,
      damlValueEncoding: opts.damlValueEncoding,
      afterMigrationId,
      afterRecordTime,
      asOfRound,
      onProgress,
    });

    process.stdout.write(JSON.stringify(bal, null, 2));
    process.stdout.write("\n");
  });

program
  .command("holdings-summary")
  .description("Balance/fees summary from Scan aggregates (/v0/holdings/summary)")
  .option("--party <partyId>", "Party ID to query")
  .option("--party-ids <csv>", "Comma-separated party IDs to query")
  .option("--validator <key>", "Known validator key (see: canton-scan validators)")
  .option("--as-of-round <n>", "Compute holdings as of this round")
  .option("--migration-id <n>", "Scan migration id (optional; auto-detected if omitted)")
  .option("--record-time <iso>", "Record time (ISO-8601; optional; auto-detected if omitted)")
  .option("--record-time-match <mode>", "Record time match mode (default: exact)")
  .option("--before <iso>", "Used only for record_time auto-detect (default: now)")
  .action(async (opts) => {
    const cfg = getDefaultScanConfig(process.env);

    const party = opts.party as string | undefined;
    const partyIdsCsv = opts.partyIds as string | undefined;
    const validatorKey = opts.validator as string | undefined;

    const selectors = [party ? "party" : null, partyIdsCsv ? "party-ids" : null, validatorKey ? "validator" : null].filter(
      Boolean
    );
    if (selectors.length !== 1) {
      throw new Error("Provide exactly one selector: --party, --party-ids, or --validator");
    }

    let partyIds: string[];
    if (party) {
      partyIds = [party];
    } else if (partyIdsCsv) {
      partyIds = String(partyIdsCsv)
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean);
    } else {
      partyIds = [resolveValidatorParty(String(validatorKey))];
    }

    const asOfRound = opts.asOfRound !== undefined ? Number(opts.asOfRound) : undefined;
    if (asOfRound !== undefined && (!Number.isFinite(asOfRound) || asOfRound <= 0)) {
      throw new Error("Invalid --as-of-round");
    }

    const migrationIdOpt = opts.migrationId !== undefined ? Number(opts.migrationId) : undefined;
    const migrationIdEnv = process.env.MIGRATION_ID !== undefined ? Number(process.env.MIGRATION_ID) : undefined;
    const migrationId = migrationIdOpt ?? migrationIdEnv;
    if (migrationId !== undefined && (!Number.isFinite(migrationId) || migrationId < 0)) {
      throw new Error("Invalid --migration-id / MIGRATION_ID");
    }

    const recordTime = (opts.recordTime as string | undefined) ?? process.env.RECORD_TIME;
    const recordTimeMatch =
      (opts.recordTimeMatch as string | undefined) ?? process.env.RECORD_TIME_MATCH ?? "exact";
    const before = (opts.before as string | undefined) ?? process.env.BEFORE;

    const resp = await fetchHoldingsSummary(cfg, {
      ownerPartyIds: partyIds,
      asOfRound,
      migrationId,
      recordTime,
      recordTimeMatch,
      before,
    });

    const rows = resp.summaries ?? resp.items ?? [];

    // If the user asked for a single party, print a single object for convenience.
    if (partyIds.length === 1) {
      process.stdout.write(JSON.stringify(rows[0] ?? null, null, 2));
      process.stdout.write("\n");
      return;
    }

    process.stdout.write(JSON.stringify(rows, null, 2));
    process.stdout.write("\n");
  });

program.parseAsync(process.argv).catch((err) => {
  process.stderr.write(String(err?.stack ?? err));
  process.stderr.write("\n");
  process.exit(1);
});
