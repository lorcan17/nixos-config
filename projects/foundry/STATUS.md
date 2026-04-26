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
ingest-paperless-hook (auto-detect parser → parse → PATCH metadata → bronze insert)
    ↓
embed-enrich.timer (every 15min, picks up unenriched bronze rows)
    ↓
finance-dbt.timer (every 15min, offset; seeds + incremental run)
```

#### 5a — `statement-extract` repo changes
- [x] **Factor out auto-detect helper** _(2026-04-25)_ — `detect.py` exposes `PARSERS`, `detect_parser`, `derive_metadata`. Returns raw holder string; owner-key mapping is a caller concern.
- [x] Add `bank_pdf_extract.detect` to public API.
- [x] Validation policy resolved — all six parsers already returned `list[str]` (no raising), so no parser-side change needed. Issues recorded on bronze rows in 5b.
- [x] Bump 0.0.1 → 0.1.0, pushed, `nix-config/flake.lock` updated _(2026-04-25)_.

#### 5b — `finance-lake` repo changes (storage-agnostic ingestion)

**Design principle: bronze is the system of record; storage (Paperless / S3 / Drive / local) is a file cache.** Hexagonal layering — a storage-agnostic core with thin adapters per backend. Avoids coupling to Paperless so we can switch storage later without touching parsing/bronze logic.

**Repo layout** — ingestion is its own top-level folder in `finance-lake`, peer to `embed_enrich/`. Conceptually separate concerns (parsing/loading vs merchant normalisation), but same repo since they share the bronze schema as a contract:
```
finance-lake/
  ingest/
    core.py         # ingest_pdf(file, source, con) → IngestResult
    sources.py      # SourceRef, IngestResult dataclasses
    adapters/
      paperless.py
      local.py
      s3.py         # future
      gdrive.py     # future
  embed_enrich/     # unchanged — only merchant normalisation
  models/           # dbt
  seeds/
```

- [x] **Core ingestion module `ingest/core.py` (storage-agnostic).** _(2026-04-25)_ Public surface:
  ```python
  @dataclass(frozen=True)
  class SourceRef:
      type: Literal["paperless", "s3", "gdrive", "local", "manual"]
      id: str  # opaque id in that backend (paperless doc_id, s3 key, gdrive file_id, abs path)

  def ingest_pdf(file_path: Path, source: SourceRef, con) -> IngestResult: ...
  ```
  - Calls `detect_parser` → `parse` → `validate_internal` (issues recorded, not fatal) → `derive_metadata`.
  - Computes `sha256(file)` as idempotency key.
  - Inserts header + details into `bronze.{bank,cc}_transactions` with `(source_type, source_id, sha256, validation_issues, ...)`.
  - Returns `IngestResult{was_finance_doc, bank, owner, last4, period_start, period_end, validation_issues, was_new_row}`.
  - Knows nothing about Paperless / S3 / any storage backend.

- [x] **Adapter contract.** _(2026-04-25 — local + paperless adapters land; s3/gdrive deferred)_
  ```python
  def fetch(source: SourceRef) -> Path: ...   # download to a local tmp path
  def writeback(source: SourceRef, result: IngestResult) -> None: ...  # optional metadata sync
  ```
  Lets the rebuild script re-pull a doc from any backend years later (parser bug fix, schema change). Cheap now, expensive to retrofit.

- [x] **Paperless adapter `ingest/adapters/paperless.py`.** _(2026-04-25 — uses httpx, lazy field-id lookup, joint detection from "/" in holder, env-driven holder→owner map)_ Reads `DOCUMENT_WORKING_PATH`, `DOCUMENT_ID` from env; constructs `SourceRef("paperless", doc_id)`; calls `ingest_pdf`; if `result.was_finance_doc`, PATCHes Paperless via REST (correspondent, custom_fields[owner|last4], title, created). API token via env `PAPERLESS_API_TOKEN`; if unset, skip the PATCH (dry-run / migration mode).

- [ ] **Bank detection optimisation** _(deferred — current PDF-open detect is fast enough; revisit if Paperless OCR backlog grows)_. Use `DOCUMENT_CONTENT` env var (Paperless's pre-OCR'd text) for the parser auto-detect step where available — string-contains anchors against bank-identifying text. Falls back to opening the PDF with pdfplumber when content isn't supplied (S3, local, manual).

- [x] **New flake output `ingest-paperless-hook`** _(2026-04-25)_. Future `ingest-s3-watcher` etc. follow the same pattern.

- [x] **Bronze schema rebuild (not migration — see ADR-006).** _(2026-04-25)_ Drop + recreate with new columns: `source_type`, `source_id`, `sha256`, `validation_issues VARCHAR[]`. Owner column dropped; holder is the raw header string. `scripts/ingest_statements.py` backs up `finance.duckdb` first.
- [x] **dbt model rename** owner→holder, source_pdf→sha256 across `fact_transactions`, `dim_accounts`, `data_completeness`. _(2026-04-25 — silver+gold green: 15 models, 17 tests pass; 6734 fact rows from 341 PDFs.)_
- [x] **dim_accounts dedup** — joint cards yield one bronze row per supplementary holder; collapsed to one row per `(source_system, account_id)` with `any_value(holder)` to stop fact_transactions left-join fan-out. _(2026-04-25)_
- [ ] **dbt warn-test on non-empty `validation_issues`** — defer until first prod run shows real-world false-positive rate (12 bank rows + 365 cc rows currently flagged on the dev DB).
- [ ] **Generalised rebuild script `scripts/rebuild_from_storage.py`** — defer until S3 or another second backend is wired; current `ingest_statements.py` covers the local case.
- [x] Bump 0.1.0 → 0.2.0, pushed, `nix-config/flake.lock` updated _(2026-04-25)_.

#### 5c — `nix-config` repo changes
- [x] `paperless.nix` — post-consume hook wired (`PAPERLESS_POST_CONSUME_SCRIPT = /etc/paperless/post-consume.sh`); `PAPERLESS_FILENAME_FORMAT` updated to `{custom_fields[owner]:-_unowned}/{correspondent}/{custom_fields[last4]:-_nolast4}/{created} {title}` matching `archive.py`. _(2026-04-25)_
- [x] `foundry.nix` post-consume script env updated: `PAPERLESS_URL`, `PAPERLESS_API_TOKEN` (agenix), `FINANCE_DUCKDB`, `DIM_HOLDERS_CSV`. Seed-copy step adds `dim_holders.csv`. _(2026-04-25)_
- [x] `paperless-api-token.age` agenix secret declared, owner=paperless. _(2026-04-25)_
- [ ] **BLOCKER — `dbt-duckdb` missing from pinned nixpkgs `python312Packages`** (see ADR-007). `nix eval .#nixosConfigurations.optiplex...` fails. `foundry.nix` parked back in `modules/wip/` so optiplex rebuilds still succeed. Resolution options: (a) overlay `python312Packages.dbt-duckdb` with a manual derivation; (b) update nixpkgs flake input; (c) fetch from a community overlay. Until resolved, finance-lake's flake output cannot be referenced from a NixOS module.
- [ ] First `nixos-rebuild switch` on optiplex once dbt-duckdb resolved + `foundry.nix` moved back to `optiplex/`. Expect Paperless to migrate-create on first run.
- [ ] Update `.claude/CLAUDE.md` with: Paperless section, Foundry pipeline diagram, post-consume hook reference.

#### 5d — Paperless first-run setup
- [x] Custom fields `owner` + `last4` created (manual UI step done by user).
- [x] API token minted, saved as `secrets/paperless-api-token.age`.
- [ ] Add Uptime Kuma HTTP monitor for `paperless.${domain}` (deferred — UI step).

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

### statement-extract — coast_capital_chequing returns empty accounts on some PDFs
`joint/coast_capital_chequing/October 2024 - Monthly eStatement.pdf` parses without raising but produces a `MultiAccountDepositStatement` with `accounts=[]`. `ingest.core` now treats this as not-a-finance-doc and tags `multi_account_no_accounts` in `validation_issues`, so the rebuild doesn't fail — but the parser should be fixed. Likely a layout edge case in the October 2024 statement (page-break or section anchor change).

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
