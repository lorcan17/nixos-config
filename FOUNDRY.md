# Project Foundry

Personal finance data lake on the OptiPlex. Single source of truth for all personal financial data — investments, bank, credit card — with medallion architecture, a semantic layer, and natural-language query via OpenWebUI.

---

## Repos

| Repo | Purpose | Output |
|---|---|---|
| `questrade-extract` | Questrade API → bronze snapshots | `bronze.questrade_snapshots` |
| `bank-cc-extract` | PDF parse → bronze transactions | `bronze.bank_transactions`, `bronze.cc_transactions` |
| `finance-lake` | dbt (silver + gold) + embed-enrich service | all Silver/Gold in `finance.duckdb` |

One repo per source. The `finance-lake` repo is the transformation and semantic layer — it doesn't touch ingestion.

---

## Storage

Single DuckDB file at `/var/lib/finance-lake/finance.duckdb`, three schemas:

| Schema | Contents | Who writes |
|---|---|---|
| `bronze` | Raw, unmodified source data | Python ingestors |
| `silver` | Cleaned, normalised, enriched | dbt + embed-enrich |
| `gold` | Analytics-ready aggregates | dbt only |

The existing SQLite at `/var/lib/questrade-extract/questrade.db` remains as-is during migration. DuckDB attaches it directly via `ATTACH ... AS legacy`.

---

## Medallion rules

- **Bronze = immutable raw.** Ingestion scripts write here exactly as the source produced it. No transforms, no enrichment, no cleanup. If enrichment logic improves, you re-run against bronze.
- **Silver = curated.** dbt models + embed-enrich Python service. Merchant normalisation, category resolution, unified fact_transactions across all sources.
- **Gold = analytics.** Pure dbt SQL. Business metrics only: net worth, spending by category, portfolio performance, cash flow.

---

## Embedding pipeline

| | Detail |
|---|---|
| **Model** | `nomic-embed-text` via local Ollama (768 dimensions, on-device, no API cost) |
| **Storage** | DuckDB `vss` extension, HNSW index on `silver.dim_merchants.embedding` |
| **When it runs** | After each bronze load, before dbt |

Two distinct uses — keep them separate:

1. **Merchant normalisation** — raw description → embed → ANN match → canonical merchant + category. Builds up `silver.dim_merchants` incrementally. Low-confidence matches go to `silver.merchant_review_queue` for human confirmation.

2. **Semantic query** — embeddings on gold-layer transactions, searched at query time when the user asks a natural-language question in OpenWebUI ("show me food spending last month").

---

## Systemd pipeline chain

Each source runs on its own timer. Downstream steps chain via `ExecStartPost`:

```
questrade-extract.service  ──┐
                              ├─→ embed-enrich.service ──→ dbt-run.service
bank-cc-extract.service    ──┘
```

`dbt-run.service` is a oneshot that runs `dbt run --select silver+ gold+` against `finance.duckdb`.

---

## Sources

### Questrade
- **Type:** position/balance snapshots (daily, per symbol)
- **Grain:** account × symbol × date → market value, quantity, book cost
- **Gaps:** transaction history (buys/sells/dividends) not currently extracted — extending the extractor would unlock IRR and return calculations. Decision deferred.

### Bank statements
- **Type:** transaction ledger
- **Ingestor:** `bank-cc-extract` PDF parser (complete)
- **Grain:** account × date × amount × raw description

### Credit card statements
- **Type:** transaction ledger
- **Ingestor:** `bank-cc-extract` PDF parser (complete)
- **Grain:** card × date × amount × raw description

---

## Silver models (key tables)

```
silver.dim_accounts            — unified account list (Questrade TFSA/RRSP/cash, bank, CC)
silver.dim_merchants           — canonical merchant names + categories + embeddings
silver.dim_categories          — category taxonomy (Groceries, Transport, Dining, ...)
silver.dim_budgets             — seed file: monthly budget per category
silver.dim_category_rules      — regex fallback rules for merchant-less categorisation
silver.merchant_review_queue   — low-confidence ANN matches awaiting human confirmation
silver.transfer_review_queue   — auto-matched transfers awaiting human confirmation
silver.fact_transactions       — all money movements, normalised across all sources
silver.fact_transaction_splits — split rows for transactions spanning multiple categories
silver.fact_transfers          — matched internal transfers (excluded from spend reports)
silver.fact_portfolio_snapshots — daily position values by account × symbol
```

**Transfer matching logic** — pairs a debit on one account with a near-equal credit on another within a 3-day window. Matched pairs are excluded from all spending aggregations in Gold (otherwise a savings transfer appears as expenditure). Low-confidence auto-matches surface in `silver.transfer_review_queue`; confirmed pairs write back as ground truth.

**Recurring detection** — window function over merchant × amount; flagged if interval is regular (±3 days). Feeds `gold.recurring_transactions`.

---

## Gold models (key tables)

```
gold.net_worth_daily         — total assets minus liabilities, by day
gold.spending_by_category    — monthly spend per category (transfers excluded)
gold.cash_flow_monthly       — income vs expense summary
gold.portfolio_performance   — returns by account, overall, vs benchmark (if available)
gold.account_balances        — latest balance per account
gold.recurring_transactions  — detected recurring charges (subscriptions, bills)
gold.budget_vs_actual        — monthly spend vs dim_budgets targets, by category
```

---

## Semantic layer (for OpenWebUI NL-to-SQL)

`finance-lake/context.md` — a compact schema description generated from dbt schema YAML, describing gold-layer tables, column meanings, and FK relationships. Injected into the OpenWebUI SQL Tool as system context.

The LLM always queries Gold only. Silver is not directly queryable from OpenWebUI — it's an implementation detail of the pipeline.

---

## Curation UI

Human-in-the-loop merchant review: `silver.merchant_review_queue` flags low-confidence matches. A lightweight admin interface (implementation TBD — see open decisions) allows confirming or correcting them. Confirmed matches write back to `silver.dim_merchants` as ground truth.

**No third-party budgeting app** (Firefly III, Sure, Actual Budget) is used as an intermediary system of record. See DECISIONS.md for rationale.

---

## OpenWebUI integration

Two OpenWebUI Tools provisioned via a systemd oneshot after rebuild:

| Tool | What it does |
|---|---|
| `finance_sql` | Accepts LLM-generated SQL, executes read-only against gold layer, returns JSON |
| `finance_chart` | Renders JSON data as an inline chart (via chart visualiser plugin) |

The SQL tool has the gold-layer schema in its docstring so the model can generate correct SQL. The `open-webui` service user needs read access to `finance.duckdb`.

---

## Open decisions

- [ ] Curation UI — lightweight Flask/HTMX admin vs OpenWebUI-native workflow
- [ ] Questrade transaction history — extend extractor to capture buys/sells/dividends (enables IRR, realised gains)
- [ ] DuckDB VSS availability in nixpkgs — may need a Python package overlay for the `vss` extension
- [ ] bank-cc-extract — which specific banks/cards; PDF format variations
- [ ] Backup strategy for `finance.duckdb` — include in restic when `backups.nix` lands
