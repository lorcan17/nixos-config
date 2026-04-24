# Foundry — Status

> Kanban for Project Foundry (personal finance data lake). See [SPEC.md](./SPEC.md) for architecture, [DECISIONS.md](./DECISIONS.md) for ADRs. Last updated: 2026-04-23.

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
- Push `statement-extract` + `finance-lake` to GitHub.
- `flake.nix` inputs + `modules/optiplex/foundry.nix`.
- New agenix secret: `openai-api-key`.
- systemd chain: questrade-extract + statement-extract → embed-enrich → dbt-run.
- Uptime Kuma push monitors (manual UI).

### Step 5 — OpenWebUI tools (OptiPlex-only)
`finance_sql` + `finance_chart` provisioned via oneshot after rebuild. Grant `open-webui` read on `finance.duckdb`.

### Step 6 — Housekeeping
- Add `/var/lib/finance-lake/` to restic include list (blocked on `backups.nix`).
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
