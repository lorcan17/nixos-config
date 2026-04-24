# Foundry — Decisions

> ADR-lite log scoped to Project Foundry. Architectural decisions that affect multiple components and/or reverse course from SPEC.md. Index newest-first.

| ID | Date | Decision |
|---|---|---|
| ADR-005 | 2026-04-23 | Rule-based pre-pass + description normalisation before embedding; salvages `personal-finance-lakehouse` rule corpus |
| ADR-004 | 2026-04-23 | DuckDB `vss` viable; enable HNSW persistence via `hnsw_enable_experimental_persistence` |
| ADR-003 | 2026-04-23 | Dev loop runs on Mac first; NixOS wiring only after Mac-side pipeline is green |
| ADR-002 | 2026-04-23 | Embeddings via OpenAI `text-embedding-3-small`, not local Ollama |
| ADR-001 | 2026-04-23 | Three-repo split (`questrade-extract`, `bank-cc-extract`, `finance-lake`); `nix-config` orchestrates only |

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
