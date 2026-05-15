# Foundry — Decisions

> ADR-lite log scoped to Project Foundry. Architectural decisions that affect multiple components and/or reverse course from SPEC.md. Index newest-first.

| ID | Date | Decision |
|---|---|---|
| ADR-014 | 2026-05-14 | Use ext4 for `/lake/` now; defer ZFS until a second disk is added to the OptiPlex |
| ADR-013 | 2026-05-14 | Decision intelligence as north star — every ingest domain modelled as thesis → decision → outcome; Brier calibration in gold layer |
| ADR-012 | 2026-05-14 | Consolidate `finance-lake` into single `foundry` repo; `statement-extract` + `questrade-extract` remain as pinned library deps; supersedes ADR-001 |
| ADR-011 | 2026-05-13 | Migrate Open-WebUI from `services.open-webui` NixOS module to OCI container (`virtualisation.oci-containers`) |
| ADR-008 | 2026-04-26 | Migrate Python services from `buildPythonPackage` to `uv run --frozen` in systemd; Nix only for system layer |
| ADR-007 | 2026-04-26 | `dbt-duckdb` 1.10.1 packaged inline in `finance-lake/flake.nix`; avoid `python.override` to keep binary cache valid |
| ADR-006 | 2026-04-25 | Drop-and-recreate bronze on every rebuild rather than migrate in place |
| ADR-005 | 2026-04-23 | Rule-based pre-pass + description normalisation before embedding; salvages `personal-finance-lakehouse` rule corpus |
| ADR-004 | 2026-04-23 | DuckDB `vss` viable; enable HNSW persistence via `hnsw_enable_experimental_persistence` |
| ADR-003 | 2026-04-23 | Dev loop runs on Mac first; NixOS wiring only after Mac-side pipeline is green |
| ADR-002 | 2026-04-23 | Embeddings via OpenAI `text-embedding-3-small`, not local Ollama |
| ADR-001 | 2026-04-23 | Three-repo split (`questrade-extract`, `bank-cc-extract`, `finance-lake`); `nix-config` orchestrates only |

---

## ADR-014 — Use ext4 for `/lake/` now; defer ZFS until second disk

**Date:** 2026-05-14
**Status:** Accepted

**Context.** The OptiPlex has a single 476.9G ADATA SU650 SSD, fully partitioned (511M /boot + 476.4G / ext4). ZFS requires a dedicated disk or partition — carving the live root partition is too risky. A 2.5" SATA SSD (~$60–80 CAD) would fit the second bay, but isn't available yet.

**Decision.** `/lake/` lives under `/var/lib/foundry/lake/` on the existing ext4 root partition. The `LAKE_ROOT` env var in `foundry.nix` is the only coupling point — migrating to ZFS later requires updating one env var and moving the files, no application code changes.

When a second disk is added: create `lake` zpool, `zfs create` the dataset hierarchy, `mv /var/lib/foundry/lake/* /lake/`, update `LAKE_ROOT`, promote `modules/wip/lake-storage.nix` to `modules/optiplex/`.

**What you lose by staying on ext4:**

| Loss | Severity | Mitigation |
|---|---|---|
| **No block-level checksumming** | High — silent bit rot goes undetected | `sha256` in every `.meta.json` sidecar detects corruption at read time, not proactively |
| **No atomic snapshots** | Medium — can't instantly roll back a bad ingest run | restic backups cover this; `finance.duckdb` `.bak.<ts>` copies cover the DB case |
| **No transparent compression** | Low — bronze files take more space | lz4 on parquet/CSV is modest; disk is 476G so not urgent |
| **No per-dataset tuning** | Low — can't set recordsize per layer | irrelevant at current data volumes |
| **No `zfs send` incremental backups** | Low — restic fills this role | restic already planned in Step 7 housekeeping |
| **No proactive scrubbing** | Medium — weekly integrity checks won't run | manual `sha256sum` sweep scriptable if wanted |

The most meaningful loss is proactive integrity checking. ZFS scrubs verify every block against its checksum on a schedule — ext4 has no equivalent. The `.meta.json` sha256 sidecar detects corruption only when a file is read. For a personal homelab this is acceptable; for a production data lake it would not be.

**Consequences.**
- `modules/optiplex/lake-storage.nix` drafted now as `modules/wip/lake-storage.nix` — ready to promote when disk arrives.
- Step 8b in STATUS.md rewritten: create `/var/lib/foundry/lake/{bronze,silver,inbox}` via `systemd.tmpfiles`, no ZFS declarations.
- Revisit when second disk purchased. Estimated migration time: 30 minutes.

---

## ADR-013 — Decision intelligence as the north star

**Date:** 2026-05-14
**Status:** Accepted

**Context.** Planning session 2026-05-14 — the question "what is this system actually for?" surfaced a clearer answer than "personal finance analytics." The system's durable value is a corpus of timestamped, calibrated decisions linked to measurable outcomes. Analytics dashboards are a consumer of that corpus, not the point of it. Most people who trade or bet have zero data on their own decision quality; this system produces exactly that data as a side effect of normal operation.

**Decision.** Every ingest domain is modelled around the thesis → decision → outcome loop:
- Obsidian investment notes: frontmatter convention (`ticker`, `decision_date`, `decision_type`, `confidence`, `thesis`) → `silver.investment_theses` → joined to Questrade P&L in gold
- Polymarket bets: open positions + resolution outcomes → `silver.prediction_market_bets` → Brier score per bet
- Future domains (hiring, real estate, technology bets) follow the same pattern — each is an ingest script + a silver model

Calibration scoring (Brier score by domain/category) is a first-class gold model, not an afterthought. The Evidence dashboard includes a calibration curve page.

**Why Brier score.** It rewards honest probability estimates — saying 90% when you win is only better than 70% if you're actually right 90% of the time. It's the standard in forecasting literature (Good Judgment Project, Metaculus) and computable with a single SQL expression: `(confidence - outcome)^2`.

**Consequences.**
- Obsidian investment note template needs a frontmatter block. New notes only; no backfill of old notes.
- Polymarket ingest requires an API key and an open positions workflow.
- `silver.investment_theses` and `silver.prediction_market_bets` are new dbt models (Step 7 in STATUS.md).
- Long-term: the calibration corpus is the defensible asset. Software can be replicated; 3 years of timestamped decisions with outcomes cannot.

---

## ADR-012 — Consolidate pipeline into `foundry` repo; supersede ADR-001

**Date:** 2026-05-14
**Status:** Accepted — supersedes ADR-001

**Context.** ADR-001 established a three-repo split: `questrade-extract`, `statement-extract`, `finance-lake`. After building Steps 3–6, the friction is clear: `finance-lake` has no good home for ingest scripts (thin wrappers that call the library repos and land data), dbt models are fine where they are, and the NixOS orchestration in `foundry.nix` is doing too much work that belongs in the pipeline repo.

**Decision.** `finance-lake` is renamed and restructured into `foundry`. It owns:
- `ingest/` — one script per source, each a thin wrapper calling the appropriate library and `land()`
- `ingest/_lib/bronze.py` — the single `land()` function; only thing that writes to `/lake/bronze/`
- `dbt/` — models and seeds (unchanged)
- `mcp/` — future MCP server
- `nix/` — NixOS modules exported by the flake (`lake-storage.nix`, `lake-ingest.nix`)

`statement-extract` and `questrade-extract` remain as **separate library repos** — they're complex enough (PDF parsing, OAuth flows) to warrant isolation. `foundry/pyproject.toml` references them as pinned git deps. When a library needs a new version: bump the tag in `pyproject.toml`, run `uv lock`, push, bump `flake.lock` in nix-config.

The rule: if an ingest concern is complex enough to have its own test suite and release cycle, it's a library. If it's a thin wrapper that calls a library and calls `land()`, it lives in `foundry/ingest/`.

**ZFS addition.** Alongside this restructure, `/lake/` moves to a ZFS pool (`lake`) on a dedicated disk. Bronze files live at `/lake/bronze/<domain>/<source>/<YYYY-MM-DD>/`. `finance.duckdb` moves to `/lake/silver/`. ZFS provides compression (lz4 on bronze), scrubbing, and snapshots without application changes. Declared in `modules/optiplex/lake-storage.nix`.

**Consequences.**
- `flake.nix` input renamed: `finance-lake` → `foundry`.
- `modules/optiplex/foundry.nix` updated to reference `inputs.foundry`.
- Spare disk required on OptiPlex before ZFS work begins.
- Cross-repo dep updates gain an extra step (tag bump + uv lock) — accepted as the price for clean library boundaries.
- ADR-007's inline `dbt-duckdb` derivation is moot once `foundry` fully migrates to `uv run --frozen` (ADR-008).

---

## ADR-011 — Migrate Open-WebUI to OCI container

**Date:** 2026-05-13
**Status:** Accepted

**Context.** `services.open-webui` (the NixOS module) ships a fixed Python env. Installing `duckdb` via pip into `PIP_TARGET` at startup conflicted with Open-WebUI's own pydantic/httpx — the finance tools were broken and a `claude-agent-sdk` pipe was completely blocked. The module was also pinned to an older version; v0.9.1+ adds a native Anthropic connector that eliminates the need for custom pipes.

**Decision.** Rewrite `modules/optiplex/open-webui.nix` to use `virtualisation.oci-containers.containers.open-webui` with image `ghcr.io/open-webui/open-webui:v0.9.5`. Key points:
- `--network=host` — Ollama on `127.0.0.1:11434` reachable; Open-WebUI on host port 8080.
- `open-webui-pip-deps` oneshot installs `duckdb` into a persistent volume-mounted dir (`/var/lib/open-webui/site-packages`) before container starts; `PYTHONPATH=/extra-packages` picks it up. Skips re-install if already present.
- `open-webui-env-prep` oneshot writes agenix secrets to `/run/open-webui-secrets/env` at boot.
- Caddy CSP header updated to allow `cdn.jsdelivr.net` and `cdnjs.cloudflare.com` for Chart.js in inline-visualizer-v2.

**Tradeoff.** Loses the declarative `services.open-webui.*` NixOS API; container state is opaque. Accepted — Open-WebUI is inherently stateful (chat history, user settings, tool files all in the volume), and the container image's isolated Python env eliminates all packaging conflicts permanently.

**Consequences.**
- `finance_tools.py` uses Python `duckdb` API (not CLI); confirmed working in container.
- Future Open-WebUI upgrades are a one-line image tag bump + `nixos-rebuild switch`.
- Adding Python packages to the container: add to the `pip install` list in `open-webui-pip-deps`.

---

## ADR-001 — Three-repo split; `nix-config` orchestrates only

**Date:** 2026-04-23
**Status:** Accepted

**Context.** FOUNDRY.md §"Repos" already proposes three repos but the kickoff question was whether to collapse Foundry into `nix-config`. `questrade-extract` and `finance-digest` are already structured this way in `modules/optiplex/finance.nix` (flake = false inputs, systemd units in nix-config).

**Decision.** Each pipeline stays in its own repo:
- `github:lorcan17/questrade-extract` (exists)
- `github:lorcan17/statement-extract` (renamed from `bank-pdf-extract` on 2026-04-23; `bank-cc-extract` was considered but rejected — covers both bank and credit card statements)
- `github:lorcan17/finance-lake` (new — dbt + `embed_enrich`)

`nix-config` holds **only** orchestration: `systemd.services.*`, `age.secrets.*`, `systemd.tmpfiles.rules`, and the `flake = false` inputs block.

**Consequences.** Pipeline iteration does not require nix-rebuild churn once the input is pinned. Downside: bumping `flake.lock` to pick up pipeline changes is an extra step — mitigated by the Mac-first dev loop (ADR-003) and eventually by the Tier 1.5 WIP dev workflow (Syncthing + `--override-input`).

---

## ADR-002 — Embeddings via OpenAI `text-embedding-3-small`

**Date:** 2026-04-23
**Status:** Accepted — supersedes SPEC.md §"Embedding pipeline"

**Context.** SPEC.md specified `nomic-embed-text` via local Ollama (768 dim, on-device, no API cost). The OptiPlex is CPU-only; inference latency for even small embedding models blocks the iteration loop during merchant normalisation development.

**Decision.** Use OpenAI `text-embedding-3-small` (1536 dim) via API. New agenix secret `openai-api-key` (this also satisfies the planned TTS secret slot — single key, two uses).

**Consequences.**
- Cost: negligible at personal-finance volume (~$0.02/M tokens; merchant strings are tiny).
- External dependency on OpenAI — acceptable given non-sensitive payloads (merchant descriptions only; no PII/amounts sent).
- HNSW index in DuckDB `vss` still used as before — only the embedding source changes.
- Revisit if privacy concerns emerge or if a local GPU lands (see PROJECT_STATUS Tier 2 TTS hardware decision).

---

## ADR-004 — DuckDB `vss` extension viable; HNSW persistence via experimental flag

**Date:** 2026-04-23
**Status:** Accepted — closes SPEC.md open decision #3

**Context.** SPEC.md flagged uncertainty about `vss` availability in nixpkgs. Tested on Mac first (DuckDB 1.4.4 from `terminal-tools.nix`).

**Decision.** Use `duckdb` packaged in nixpkgs; `INSTALL vss; LOAD vss;` works. HNSW indexes on a persistent (file-backed) database require:
```sql
LOAD vss;  -- must precede the SET
SET hnsw_enable_experimental_persistence = true;
```
Set this in `embed_enrich` connection setup and in `dbt_project.yml` `on-run-start` hooks.

**Consequences.**
- "Experimental" label is DuckDB's own; for a single-user personal dataset the risk is acceptable. Revisit if a future DuckDB release makes it stable (drop the flag) or breaks persistence (rebuild index on load).
- No Python/nixpkgs overlay needed — standard `pkgs.duckdb` is sufficient. Open decision #3 closed.

---

## ADR-005 — Rule-based pre-pass + description normalisation before embedding

**Date:** 2026-04-23
**Status:** Accepted — amends SPEC.md §"Embedding pipeline"

**Context.** First embed_enrich run on Mac bronze (1653 distinct raw descriptions from 342 PDFs + Questrade snapshots) produced 802 merchants and 851 review-queue entries — ~51% of descriptions landed in the 0.15–0.30 cosine-distance review band. OpenAI `text-embedding-3-small` tends to cluster Vancouver merchant strings at 0.2–0.4, so the review queue is dominated by near-duplicates ("SQ \*PUREBREAD BAKERY I Vancouver BC" vs "PUREBREAD 4TH Vancouver BC") rather than genuine low-confidence matches. Separately, `~/Library/Mobile Documents/…/personal-finance-lakehouse` has a mature YAML rule corpus (~150 patterns covering Vancouver merchants, Canadian banks, transit) accumulated over prior iterations.

**Decision.** Two pre-embedding steps added to `embed_enrich.normalise`:

1. **Description cleaning** (`clean()`): strip processor prefixes (`SQ *`, `BAM*`, `TST*`), `USD <amount>@<rate>` FX annotations, phone numbers, store-number markers (`#12345`), long digit runs, trailing `<City> <Province>` tokens, bare province codes. Cleaned form becomes both the embedding input and the stored `canonical_name`, with dedup on cleaned name across phases.
2. **Deterministic rule pre-pass**: new seed `seeds/dim_category_rules.csv` ported from the old repo's YAML → `silver.dim_category_rules`. `embed_enrich` loads the CSV directly (avoids chicken-and-egg with `dbt seed` which runs after enrichment). First-match-by-priority wins; rule-matched merchants get inserted with their resolved `category_id` and **skip embedding entirely** — no API call, no ANN lookup, no review queue.

Thresholds widened from `≤0.15 / ≥0.30` to `≤0.22 / ≥0.35` to reflect text-embedding-3-small's distance distribution on merchant strings.

**Consequences.**
- Review queue: 851 → 174 entries (~79% reduction) on the same bronze input. 553 merchants (56%) categorised deterministically with zero API cost.
- SPEC.md §"Silver models" already lists `silver.dim_category_rules` — this closes that implementation gap.
- `canonical_name` in `dim_merchants` is now the *cleaned* form, not the original raw description. `fact_transactions` still joins by raw description via the merchant lookup path (to be built in dbt silver layer) — the cleaned form is for matching, not display.
- Rule maintenance is now a normal seed-file workflow: edit CSV, `dbt seed`, re-run enrichment on new bronze.
- OpenAI cost dropped proportionally — only ~440 distinct non-rule-matched descriptions hit the API per full rebuild.
- Tech debt logged separately in STATUS.md — several improvements deferred (embed-branch dedup, regex rules, HNSW tuning, canonical display name, reference counting).

---

## ADR-003 — Mac-first dev loop

**Date:** 2026-04-23
**Status:** Accepted

**Context.** The Tier 1.5 "WIP project dev workflow" backlog item (Syncthing + `--override-input` vs. rebuild-per-iteration) is unresolved. Foundry's dbt model work is highly iterative — waiting on it would block Foundry indefinitely. Separately, the user requested end-to-end testing on Mac before deployment.

**Decision.** `finance-lake` is developed entirely on Mac against a local DuckDB at `~/.local/share/finance-lake/finance.duckdb`. dbt profile has `dev` (Mac path) and `prod` (OptiPlex path) targets. Bronze inputs on Mac come from scp'd snapshots of OptiPlex SQLite + sample PDFs. Production wiring into NixOS happens **only after** all seven smoke-test steps pass on Mac (STATUS.md Step 3).

**Consequences.**
- No Nix module churn while iterating on models/taxonomy/merchant rules.
- Mac becomes Foundry's primary dev environment — fine for single-author project.
- Bronze-on-Mac requires a short-lived bootstrap script (`scp` + `ATTACH`) — lives in `finance-lake/scripts/dev_bootstrap.py`, not shipped to prod.
- Sidesteps Tier 1.5 WIP workflow decision for Foundry specifically; that decision can still be made separately for other pipelines.

---

## ADR-006 — Bronze rebuild over migration

**Date:** 2026-04-25
**Status:** Accepted

**Context.** Step 5b adds new columns to `bronze.{bank,cc}_transactions` (`source_type`, `source_id`, `sha256`, `validation_issues`) and renames `owner` → `holder`. STATUS.md originally listed a backfill migration. Bronze is small (<10k rows) and re-derivable from PDFs.

**Decision.** Drop and recreate bronze on every rebuild rather than migrate in place. `scripts/ingest_statements.py` copies `finance.duckdb` to a timestamped `.bak.<ts>` sibling before any destructive op so post-run row counts and column distributions can be diffed against the prior run.

**Consequences.**
- No migration code to maintain or test.
- Schema evolution is just a code edit + rerun; rollback is a `cp` of the backup.
- Backup file accumulates — housekeeping should prune `*.bak.*` >30 days old (deferred).
- Once finance-lake gains an event-sourced rebuild from cold storage (Step 5b's `rebuild_from_storage.py`), the local archive walk becomes one of several rebuild sources and the same backup discipline applies.

---

## ADR-007 — `dbt-duckdb` packaged inline in finance-lake's flake

**Date:** 2026-04-25 (opened) / 2026-04-26 (resolved)
**Status:** Accepted

**Context.** Step 5c brings `finance-lake.packages.${system}.default` (which embeds `dbt-duckdb` in `pythonEnv`) into optiplex's NixOS configuration via `foundry.nix`. Pinned nixpkgs lacks `python312Packages.dbt-duckdb`, so `nix eval .#nixosConfigurations.optiplex` was failing.

**Survey.** No reusable community overlay exists. Upstream nixpkgs PR [#457151](https://github.com/NixOS/nixpkgs/pull/457151) (init at 1.9.6) has been open and stale for ~3 months. The four runtime deps (`dbt-core`, `dbt-adapters`, `dbt-common`, `duckdb`) are already in our pinned nixpkgs.

**Decision.** Define `dbt-duckdb` 1.10.1 inline in `finance-lake/flake.nix` as a `buildPythonPackage` derivation (within `perSystem`), and add it to `pythonEnv` directly via `withPackages`. Avoid `python312.override { packageOverrides }` — that would invalidate the binary cache for the entire python312 set and force every dep (polars, pandas, dbt-core, …) to rebuild from source.

**Why finance-lake, not nix-config.** `finance-lake.packages.${system}.default` is built inside finance-lake's flake using its own `pkgs`. An overlay in nix-config doesn't reach that build. The dependency is finance-lake's, so it owns the derivation.

**Consequences.**
- `foundry.nix` lives in `modules/optiplex/`; optiplex eval succeeds.
- Drop the inline derivation once nixpkgs PR #457151 lands and we bump the input.
- Hash pinned to source tarball at tag `1.10.1` — version bumps require updating both `version` and `hash`.

---

## ADR-008 — Python services use `uv run --frozen` in systemd, not `buildPythonPackage`

**Date:** 2026-04-26
**Status:** Accepted (spike landed in `modules/wip/foundry-uv.nix`; full migration deferred until smoke test passes)

**Context.** Step 5c required `finance-lake.packages.${system}.default` to build on optiplex. Getting there cost a multi-hour grind:
- `dbt-duckdb` missing from nixpkgs entirely (ADR-007 inline derivation).
- Spurious namespace collision between `dbt-core` and `dbt-adapters` (`dbt/include/__init__.py`) requiring `python.buildEnv` with `ignoreCollisions = true`.
- `statement-extract` initially shipped as `buildPythonApplication`, hiding its modules from consumer envs — switched to `buildPythonPackage`.
- Cache misses on transitive scientific Python deps (polars rust compile, ndindex/blosc2 pytest suites at 20+ min each) on both aarch64-darwin and x86_64-linux. None of these packages are used directly by Foundry.

All of this is *Nix Python packaging* friction. None of it is *Nix system tool* friction. NixOS-the-system (services, agenix, systemd, caddy) was flawless throughout.

**Decision.** Going forward, Python services in this repo are deployed via:
- `pkgs.uv` from nixpkgs (small, well-cached).
- Source tree from a flake input.
- `ExecStart = "${pkgs.uv}/bin/uv run --frozen python -m <mod>"`.
- Venv + uv cache under a systemd `StateDirectory` so they survive rebuilds and only re-sync when `uv.lock` changes.

`uv.lock` provides sufficient determinism for single-author homelab use; PyPI wheels are seconds, not minutes; uv is already the Mac dev tool, removing a dev/prod tooling gap.

**Inter-repo dep handling (chosen path).** Drop the editable `path = "../statement-extract"` in `finance-lake/pyproject.toml`; replace with a pinned git source. Cost: a commit/push/`uv lock` cycle on every cross-repo change. Accepted as the price for a uniform build path on Mac and prod.

**Consequences.**
- New Python services: scaffold with `uv init` + `uv.lock` from the start; never write a Nix derivation.
- Existing services using `buildPythonPackage` (foundry's three units, finance.nix's questrade-extract + finance-digest): leave alone unless touching them; opportunistic migration when next change is needed.
- Generalises beyond Foundry — applies to all future personal Python projects.
- ADR-007's inline `dbt-duckdb` derivation goes away entirely once foundry migrates to uv (deps come from PyPI).
- `nixos-rebuild switch` on optiplex becomes seconds (no Python compile), restoring fast iteration.

---

## ADR-009 — Net worth time-series from forward-filled bank statements

**Date:** 2026-04-28
**Status:** Accepted (live in `finance-lake/models/gold/positions/net_worth_daily.sql`)

**Context.** v1 of `net_worth_daily` summed Questrade portfolio market values per snapshot date. With Questrade snapshots starting 2026-04-17, the gold mart had **4 rows**, useless for any growth-over-time visual. Bank-statement headers (`bronze.bank_statements.closing_balance`) cover **2022-01-05 → 2026-04-20** across 8 active deposit accounts — all the depth was sitting unused in bronze.

**Decision.** Replace `net_worth_daily` with a forward-filled bank-balance time series:
- For each `(holder, account_number)`, each statement contributes its `closing_balance` to the window `[period_end, next_statement.period_end)`.
- The latest statement extends to `current_date + 1 day`.
- Cross join with a daily date spine; sum `closing_balance` across accounts per day.
- Result: **1575 rows**, daily granularity, ~$40k → $112k cumulative growth visible.

**Excluded from v2 scope.**
- Questrade portfolio market value — sparse, has its own page.
- Credit card `total_balance` as a liability — straightforward follow-up; deferred to keep this change tight.

**Consequences.**
- Dashboards (Evidence) show meaningful growth-over-time on the net-worth page.
- `total_liabilities` is hardcoded `0` in v2 — column kept for future CC integration.
- Adds `n_accounts_contributing` for sanity-checking that all expected accounts are represented on a given day.
- Date spine uses `generate_series(min(period_end), current_date)` — recomputes on every dbt run; cheap at homelab scale.

---

## ADR-010 — Categorisation chain on `fact_transactions` with transfer-detection-first

**Date:** 2026-04-28
**Status:** Accepted (live in `finance-lake/models/silver/ledger/fact_transactions.sql`)

**Context.** Two structural bugs were producing 100% `uncategorised` in `gold.spending_by_category`:
1. `silver/ledger/dim_merchants.sql` was a stub creating an empty table — embed_enrich was writing to `silver.dim_merchants` (separate schema) and the dbt-materialised `main_silver.dim_merchants` stayed empty forever.
2. `fact_transactions.merchant_id` was hardcoded `NULL` — no lookup against `dim_merchants` was wired in, so even with merchants populated, facts couldn't enrich.

A naive substring-match fallback against `dim_category_rules` then surfaced a third issue: the rule pattern `nsf` matches *inside* "tra**nsf**er", routing $551k of inter-account transfers into "fees".

**Decision.** Categorisation now lives on `fact_transactions` itself with this precedence chain:
1. **`dim_category_overrides`** (manual override keyed on `stable_id`) — highest precedence.
2. **Transfer detection** (runs second, preempts substring rules) — sources are `dim_transfer_rules`, `dim_category_rules` where category=`transfer`, plus regex catch-alls for `\btransfer\b` / `\btf\d+`.
3. **Merchant** — `dim_merchants.canonical_name = clean_description` exact match (`'uncategorised'` rows fall through to step 4).
4. **Substring rule** — `arg_min(category_id, priority)` over `dim_category_rules` patterns contained in `clean_description`, *excluding* transfer-category rules (transfer is settled in step 2).
5. Default `'uncategorised'`.

`dim_merchants` model rewritten as a passthrough view over the `silver.dim_merchants` source so embed_enrich's writes are immediately visible to downstream models without a dbt re-run.

`category_source` column added (`override` / `transfer-detect` / `merchant` / `rule` / `default`) for diagnostic purposes.

**Outcome.** From 0/6734 → 6734 facts categorised across 928 transfers + 868 rule + 156 merchant + 4782 still-`uncategorised`. Real-spend distribution now shows rent ($101k), groceries, dining, utilities, etc.

**Known gaps (tech debt).**
- Most facts (~70%) still default to `uncategorised` because `clean_description` and `canonical_name` rarely match exactly — embed_enrich's cleaning is more aggressive. Future work: have embed_enrich write a `clean_description → merchant_id` lookup table, or align cleaning regex.
- Substring rules use `contains()` not word-boundary regex — covered by the transfer-first ordering for the worst false-positives, but other patterns (e.g. short tokens) may still misfire.
- Hardcoded transfer regex `\btransfer\b` should ideally come from a curated rule set, not be inline in the model.
