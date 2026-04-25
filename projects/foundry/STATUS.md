# Foundry — Status

> Kanban for Project Foundry (personal finance data lake). See [SPEC.md](./SPEC.md) for architecture, [DECISIONS.md](./DECISIONS.md) for ADRs. Last updated: 2026-04-24.

## In Flight

### Step 3 — Mac end-to-end smoke test (GATE)
Full pipeline green on Mac before any NixOS work:
- [x] scp `questrade.db` from OptiPlex _(via `scripts/dev_bootstrap.py`)_
- [x] ATTACH SQLite → bronze.questrade_snapshots _(44 rows, 3 accounts, 4 dates)_
- [x] statement-extract PDFs → bronze.{bank,cc}_transactions _(342/342 PDFs, 6784 rows, 2021-12 → 2026-04; all owners)_
- [x] embed_enrich runner populates silver.dim_merchants + review queue _(post-ADR-005: 995 merchants, 553 rule-categorised, 174 review-queue entries from 1653 distinct descriptions)_
- [x] `dbt run --target dev` silver+gold green _(5/5 models, 20/20 tests pass)_
- [x] `gold.net_worth_daily` returns sensible rows _(~$29k across 3 Questrade accounts)_
- [x] pytest passes _(1/1)_

## Backlog

### Step 4 — Push repos + wire NixOS orchestration
- [x] Push `statement-extract` + `finance-lake` to GitHub _(2026-04-24 — both public at `github:lorcan17/{statement-extract,finance-lake}`)_
- [x] `nix-config/flake.nix` inputs wired + locked _(2026-04-24 — Mac dry-build green)_
- [x] agenix secret `openai-api-key` _(staged in `secrets/openai-api-key.age`, wired into `modules/shared/secrets.nix` 2026-04-24)_
- [x] `modules/optiplex/foundry.nix` drafted — systemd timers for embed-enrich + finance-dbt + post-consume hook wiring _(2026-04-24)_
- [x] `modules/optiplex/paperless.nix` drafted — Paperless-ngx as the document inbox (used by Foundry + general household paperwork) _(2026-04-24)_
- [x] Uptime Kuma push monitors created — embed-enrich + finance-dbt push URLs wired into `foundry.nix` _(2026-04-24)_

### Step 5 — Paperless-driven ingestion (REPLACES the old "systemd chain" model)

**Rationale for the redesign:** instead of timer-driven extract → load → enrich → dbt, the pipeline is event-driven from the moment a PDF lands in Paperless. See [DECISIONS.md](../../DECISIONS.md) (2026-04-24 entries on n8n and review UI). Architecture:

```
PDF dropped in Paperless consume/
    ↓
Paperless OCR + post-consume hook fires
    ↓
embed-enrich-paperless-hook (auto-detect parser → parse → PATCH metadata → bronze insert)
    ↓
embed-enrich.timer (every 15min, picks up unenriched bronze rows)
    ↓
finance-dbt.timer (every 15min, offset; seeds + incremental run)
```

#### 5a — `statement-extract` repo changes
- [ ] **Factor out auto-detect helper.** Extract shared logic from `archive.py` into a public `detect.py` module with two functions:
  - `detect_parser(pdf: Path) -> ModuleType | None` — try each parser in turn; first one whose `parse()` succeeds without raising wins. Returns `None` if no parser matches (not a finance PDF).
  - `derive_metadata(header) -> tuple[owner, bank_product, last4]` — single source of truth used by both `archive.reorg` and the new Paperless hook.
- [ ] Add `bank_pdf_extract.detect` to public API (importable by finance-lake).
- [ ] Decide validation policy: Paperless hook should call `validate_internal()` and **store issues on the bronze row** (new `validation_issues TEXT[]` column) rather than refusing to ingest. Fail-loud is wrong for downstream — better to load and flag.
- [ ] Bump version, push, update `nix-config/flake.lock` via `nix flake update statement-extract`.

#### 5b — `finance-lake` repo changes
- [ ] **New module `embed_enrich/paperless_hook.py`.** Reads Paperless env vars (`DOCUMENT_WORKING_PATH`, `DOCUMENT_ID`), calls `detect_parser`, parses, calls `derive_metadata`, then:
  - sha256(file) → idempotency key on bronze insert.
  - PATCHes Paperless via REST API (`PATCH /api/documents/<id>/`): correspondent (= bank_product), custom_fields[owner], custom_fields[last4], title (`{bank} {owner} {YYYY-MM}`), created (= statement period_end). Token via env `PAPERLESS_API_TOKEN`.
  - Inserts header + details into `bronze.{bank,cc}_transactions` with `validation_issues` populated.
  - On `detect_parser` returning `None` → exit 0 (non-finance doc, no-op).
- [ ] **New flake output.** `writeShellApplication` named `embed-enrich-paperless-hook` exposing the above. Reuses existing `pythonEnv`.
- [ ] **Bronze schema migration** — add `validation_issues TEXT[]` and `source_paperless_doc_id INTEGER` columns to `bronze.bank_transactions` and `bronze.cc_transactions`. Backfill `validation_issues = []` on existing rows.
- [ ] **dbt test** — add a `silver` test that flags rows where `validation_issues` is non-empty (warn, not error — these still load, just need attention).
- [ ] **Rebuild script** — `scripts/rebuild_from_paperless.py`. Walks `/var/lib/paperless/media/documents/originals/**/*.pdf`, drops bronze tables, re-runs the hook path on each. For "I changed a parser, re-process everything" workflows.
- [ ] Bump version, push, update `nix-config/flake.lock`.

#### 5c — `nix-config` repo changes
- [x] `paperless.nix` drafted (2026-04-24). _Pending: import on optiplex host + first build._
- [x] `foundry.nix` drafted (2026-04-24). _Pending: wire `paperless-api-token` agenix secret once minted from Paperless UI._
- [ ] Update `PAPERLESS_FILENAME_FORMAT` in `paperless.nix` to match `archive.py` layout: `{custom_fields[owner]:-_unowned}/{correspondent}/{custom_fields[last4]:-_nolast4}/{created} {title}` — so a Paperless-managed file ends up identical to a manually-archived one.
- [ ] First `nixos-rebuild switch` on optiplex with `paperless.nix` + `foundry.nix` imported. Expect Paperless to migrate-create on first run.
- [ ] Update `.claude/CLAUDE.md` with: Paperless service section, Foundry pipeline diagram, post-consume hook reference, agenix `openai-api-key` + `paperless-api-token` rows in PROJECT_STATUS.md secrets table.

#### 5d — Paperless first-run setup (manual, UI-only)
- [ ] Set admin password via UI; capture in agenix as `paperless-admin-password.age` (or skip — single-user instance).
- [ ] Create custom fields: `owner` (text), `last4` (text). One-time, can't be declarative.
- [ ] Mint API token (Profile → Edit Profile → API Token). Save as agenix secret `paperless-api-token.age`. Reference in `foundry.nix` env for the post-consume script.
- [ ] No correspondent matching rules — leave empty. Hook is the source of truth.
- [ ] Import Uptime Kuma HTTP monitor for `paperless.${domain}`.

#### 5e — End-to-end smoke test
- [ ] Drop one BMO chequing statement PDF (any filename, any owner) into `/var/lib/paperless/consume/`.
- [ ] Confirm: file disappears from consume/ within ~30s; appears at `originals/lorcan/bmo_deposit_account/<last4>/...`; bronze row landed; validation_issues empty.
- [ ] Drop one Amex joint statement (Lorcan + Grace primary/supplementary). Confirm: lands at `originals/joint/amex/...`, both holder names captured.
- [ ] Drop a non-finance PDF (e.g. utility bill). Confirm: hook is no-op (exits 0), Paperless leaves it under `_unowned/` per filename format.
- [ ] Wait for `embed-enrich.timer` tick. Confirm: dim_merchants populated, review_queue updated.
- [ ] Wait for `finance-dbt.timer` tick. Confirm: gold tables refresh.
- [ ] Trigger an OpenAI-credits-out scenario manually (revoke key briefly): confirm ntfy fires; on key restore, next tick auto-resumes.

### Step 6 — OpenWebUI tools (OptiPlex-only)
`finance_sql` + `finance_chart` provisioned via oneshot after rebuild. Grant `open-webui` read on `finance.duckdb`.

### Step 7 — Housekeeping
- Add `/var/lib/finance-lake/` and `/var/lib/paperless/` to restic include list (blocked on `backups.nix`).
- Update root `PROJECT_STATUS.md` when Foundry lands.

### Transfer-matching (finance-lake / dbt)
Inter-account transfers (e.g. BMO chequing → EQ savings) currently inflate `gold.spending_by_category`. Add a silver concern that pairs opposite-sign, same-amount transactions across accounts within ±N days, exposed either as `dim_transfers` or a `fact_transactions.is_transfer` flag. Then filter `where not is_transfer` in `gold/spending_by_category.sql` (TODO already noted at line 3). Defer until ≥3 months of prod data exist to tune the matching window empirically.

### statement-extract — synthetic fixture generator (Option B)
Single Python script using `reportlab` to emit paired `(pdf, csv, expected.json)` from a list of fake transactions, mimicking BMO/Amex/EQ layouts. Lets tests and CI run without real PII. ~½ day per format; revisit when CI is wanted or when contributors are added.

### statement-extract — test refactor: expected.json pattern
Real fixtures + tests are currently gitignored to avoid PII in the source tree (assertions in `test_*.py` previously contained holder names, exact balances, merchant strings). Refactor: keep tests structural (parses, validates, types/counts non-zero); move all exact-value assertions into per-fixture `expected.json` files that live alongside the fixture in `~/Documents/finance-lake-fixtures/`. Pairs naturally with Option B above.

## Done

- **Step 0 — Tracking scaffolding** _(2026-04-23)_ — `projects/foundry/` folder with SPEC/STATUS/DECISIONS; root `PROJECT_STATUS.md` pointer + convention note.
- **Step 1 — Mac DuckDB + `vss` sanity check** _(2026-04-23)_ — `duckdb` v1.4.4 from `terminal-tools.nix`; `vss` loads; HNSW index + ANN query work with `hnsw_enable_experimental_persistence = true`. ADR-004 logged.
- **Step 2 — `finance-lake` scaffold** _(2026-04-23)_ — `~/projects/finance-lake/` with uv + dbt-duckdb, dev/prod profiles, silver models (dim_accounts, dim_merchants, fact_transactions), gold models (net_worth_daily, spending_by_category), seeds (categories, budgets), embed_enrich module with OpenAI client + HNSW ANN matcher, dev_bootstrap.py for Mac-local bronze seeding. direnv-managed OPENAI_API_KEY. git-init'd, not pushed.
- **Step 4a — Public release of statement-extract + finance-lake** _(2026-04-24)_ — both repos pushed public at `github:lorcan17/{statement-extract,finance-lake}`. PII purge landed across all 5 parsers (dynamic holder extraction via address-block walk-up + anchor regex); 16/16 pytest + 12 real-PDF validator pass; 0-row regression vs pre-change bronze DB. finance-lake restructured into `silver/ledger/` + `gold/{analytics,positions}/` with 8 new models; 4 model bugs fixed (quality_alerts self-join, semantic_transactions ref, fact_transfers 1:1 matching + outbound-only Case C). `seeds/dim_categories.csv` now committed (generic taxonomy).

## Tech debt — embed_enrich

Logged during ADR-005 tune (2026-04-23). Review after first prod run surfaces real review-queue volume.

- **Embed-branch dedup.** Rule pre-pass dedupes on cleaned `canonical_name`, but the embedding branch doesn't — two remaining descriptions that clean to the same string both embed and both insert. Low impact on the current corpus but pure waste.
- **Canonical display name.** `canonical_name` currently stores the lowercased cleaned form (`"safeway"`, `"purebread"`). Fine for matching; ugly in Gold. Separate `display_name` column (title-cased, or curated via review queue) before OpenWebUI wiring.
- **Rule engine is substring-only.** No regex, no word-boundary guarantees ("bar" matches "barbershop"). Ports 1:1 from the old repo's YAML but should move to regex with `\b` boundaries — especially for short patterns ("iga", "mec", "bar").
- **Rule priority ties.** Ordered by `priority` column then insertion order. Add an explicit `rule_id` tiebreak if two rules share a priority.
- **HNSW threshold is empirical.** `≤0.22 / ≥0.35` set from a single run's distance distribution. Re-tune once prod has ≥3 months of transactions — or switch to percentile-based thresholds over historical distances.
- **No reference counting on merchants.** Can't tell which merchants are frequently-used vs one-offs; impairs merging decisions in the review queue.
- **`dim_category_rules` loaded from CSV on disk.** Embed_enrich reads `seeds/dim_category_rules.csv` directly — works around `dbt seed` running after enrichment, but means rule edits require file presence at enrichment time. Once the silver layer stabilises, consider running `dbt seed` before `embed-enrich.service` in the systemd chain and read from `silver.dim_category_rules` instead.
- **Cleaning regex is English/Canada-specific.** Province codes (`BC`, `ON`, etc.) are Canadian; city-stripping assumes Title-case cities followed by 2-letter province. Anything international (travel charges, online US merchants) slips through cleaning and bloats the embedding side.

## Deferred

- Curation UI (SPEC open decision #1) — defer until review queue volume is known after first pipeline run.
- Questrade transaction history extension — unlocks IRR; not needed for v1.
- Migration of operational kanban to `finance-lake` repo once it exists.
