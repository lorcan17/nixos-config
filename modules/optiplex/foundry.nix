{ pkgs, config, domain, statement-extract, finance-lake, ... }:
let
  system  = pkgs.stdenv.hostPlatform.system;
  lakePkg = finance-lake.packages.${system}.default;

  # Post-consume hook — Paperless invokes for every newly-OCR'd doc.
  # Hook (in finance-lake) auto-detects parser, parses, inserts header+detail
  # rows into bronze (idempotent on sha256), and PATCHes Paperless metadata
  # so PAPERLESS_FILENAME_FORMAT auto-files the doc.
  postConsume = pkgs.writeShellScript "paperless-post-consume" ''
    set -euo pipefail
    export FINANCE_DUCKDB="/var/lib/finance-lake/finance.duckdb"
    export PAPERLESS_URL="http://127.0.0.1:28981"
    export PAPERLESS_API_TOKEN="$(cat ${config.age.secrets.paperless-api-token.path})"
    export DIM_HOLDERS_CSV="/var/lib/finance-lake/seeds/dim_holders.csv"
    exec ${lakePkg}/bin/ingest-paperless-hook
  '';
in {
  age.secrets.openai-api-key.owner = "lorcan";

  # Used by the Paperless post-consume hook to PATCH document metadata via REST.
  # Owned by the paperless system user because the hook is invoked by paperless.
  age.secrets.paperless-api-token = {
    file  = ../../secrets/paperless-api-token.age;
    mode  = "0400";
    owner = "paperless";
  };

  # The hook script lives at a stable path so paperless.nix can reference it.
  environment.etc."paperless/post-consume.sh".source = postConsume;

  # Shared state. The hook (as paperless) and embed-enrich/dbt (as lorcan) both
  # write to the DuckDB file, so the dir is owned by lorcan with paperless as
  # the group, mode 0770. lorcan must be added to the paperless group
  # (declared below) for this to work in both directions.
  systemd.tmpfiles.rules = [
    "d /var/lib/finance-lake          0770 lorcan paperless -"
    "d /var/lib/finance-lake/seeds    0770 lorcan paperless -"
    "d /var/lib/finance-lake/dbt      0770 lorcan paperless -"
  ];

  users.users.lorcan.extraGroups = [ "paperless" ];

  # --- embed-enrich ---------------------------------------------------------
  # Picks up unenriched bronze rows (merchant cleanup, embedding, category
  # assignment via dim_category_rules + LLM fallback). Idempotent — only
  # processes rows where enriched_at IS NULL.

  systemd.services.embed-enrich = {
    description = "Foundry — enrich bronze rows (merchant + category)";
    after       = [ "network-online.target" ];
    wants       = [ "network-online.target" ];
    serviceConfig = {
      Type      = "oneshot";
      User      = "lorcan";
      OnFailure = "ntfy-alert@%n.service";
      ExecStart = pkgs.writeShellScript "embed-enrich-run" ''
        export OPENAI_API_KEY="$(cat ${config.age.secrets.openai-api-key.path})"
        export FINANCE_DUCKDB="/var/lib/finance-lake/finance.duckdb"
        exec ${lakePkg}/bin/embed-enrich
      '';
      ExecStartPost = "${pkgs.curl}/bin/curl -fsS 'https://kuma.blue-apricots.com/api/push/V1hCTd4Enc6dKvBxUYNHBaViOcGQDmMk?status=up&msg=OK&ping='";
    };
  };

  systemd.timers.embed-enrich = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitInactiveSec = "15min";
      Persistent = true;
    };
  };

  # --- dbt run --------------------------------------------------------------
  # Copies the gitignored seeds (budgets, category_rules, account_normalization)
  # from /var/lib/finance-lake/seeds into the dbt project tree, then runs
  # `dbt seed && dbt run` incrementally. dim_categories.csv is in the repo.

  systemd.services.finance-dbt = {
    description = "Foundry — dbt seed + incremental run";
    after       = [ "embed-enrich.service" ];
    serviceConfig = {
      Type      = "oneshot";
      User      = "lorcan";
      OnFailure = "ntfy-alert@%n.service";
      ExecStartPre = pkgs.writeShellScript "finance-dbt-pre" ''
        # Seeds that are gitignored (PII / personal taxonomy) live outside the
        # Nix store. Copy them into the dbt project tree before each run.
        for f in dim_budgets.csv dim_category_rules.csv dim_account_normalization.csv dim_holders.csv; do
          if [ -f /var/lib/finance-lake/seeds/$f ]; then
            install -m 0640 /var/lib/finance-lake/seeds/$f \
              /var/lib/finance-lake/dbt/seeds/$f
          fi
        done
      '';
      ExecStart = pkgs.writeShellScript "finance-dbt-run" ''
        export FINANCE_DUCKDB="/var/lib/finance-lake/finance.duckdb"
        export DBT_PROFILES_DIR="/var/lib/finance-lake/dbt"
        cd /var/lib/finance-lake/dbt
        ${lakePkg}/bin/finance-lake-dbt seed
        ${lakePkg}/bin/finance-lake-dbt run
      '';
      ExecStartPost = "${pkgs.curl}/bin/curl -fsS 'https://kuma.blue-apricots.com/api/push/Dt12yqSm45yinjcd3UKIhKsv3KKDcs5f?status=up&msg=OK&ping='";
    };
  };

  systemd.timers.finance-dbt = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitInactiveSec = "15min";
      Persistent = true;
    };
  };
}
