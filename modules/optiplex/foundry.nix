{ pkgs, config, domain, statement-extract, foundry, ... }:
let
  system    = pkgs.stdenv.hostPlatform.system;
  foundryPkg = foundry.packages.${system}.default;

  # Post-consume hook — Paperless invokes for every newly-OCR'd doc.
  postConsume = pkgs.writeShellScript "paperless-post-consume" ''
    set -euo pipefail
    # Paperless runs on python 3.13 and exports PYTHONPATH pointing at its
    # 3.13 site-packages. Our hook is a python 3.12 env; without unsetting,
    # imports like `cryptography` resolve to paperless's 3.13 wheel and
    # crash on ABI-incompatible C extensions.
    unset PYTHONPATH
    export FINANCE_DUCKDB="/var/lib/foundry/lake/silver/finance.duckdb"
    export LAKE_ROOT="/var/lib/foundry/lake"
    export PAPERLESS_URL="http://127.0.0.1:28981"
    export PAPERLESS_API_TOKEN="$(cat ${config.age.secrets.paperless-api-token.path})"
    export DIM_HOLDERS_CSV="/var/lib/foundry/seeds/dim_holders.csv"
    exec ${foundryPkg}/bin/ingest-paperless-hook
  '';
in {
  age.secrets.openai-api-key.owner = "lorcan";

  # Used by the Paperless post-consume hook to PATCH document metadata via REST.
  age.secrets.paperless-api-token = {
    file  = ../../secrets/paperless-api-token.age;
    mode  = "0400";
    owner = "paperless";
  };

  environment.etc."paperless/post-consume.sh".source = postConsume;

  # Shared state directories. The hook (as paperless) and embed-enrich/dbt
  # (as lorcan) both write to the DuckDB file — dir owned by lorcan, group
  # paperless, mode 0770. lorcan must be in the paperless group.
  systemd.tmpfiles.rules = [
    "d /var/lib/foundry                      0770 lorcan paperless -"
    "d /var/lib/foundry/lake                 0770 lorcan paperless -"
    "d /var/lib/foundry/lake/bronze          0770 lorcan paperless -"
    "d /var/lib/foundry/lake/silver          0770 lorcan paperless -"
    "d /var/lib/foundry/lake/inbox           0770 lorcan paperless -"
    "d /var/lib/foundry/seeds               0770 lorcan paperless -"
    "d /var/lib/foundry/dbt                 0770 lorcan paperless -"
    "d /var/lib/foundry/dbt/seeds           0770 lorcan paperless -"
    # Z recursively normalises mode + ownership on existing files.
    "Z /var/lib/foundry                      0770 lorcan paperless -"
  ];

  users.users.lorcan.extraGroups = [ "paperless" ];

  # --- embed-enrich ---------------------------------------------------------
  systemd.services.embed-enrich = {
    description = "Foundry — enrich bronze rows (merchant + category)";
    after       = [ "network-online.target" ];
    wants       = [ "network-online.target" ];
    unitConfig.OnFailure = "ntfy-alert@%n.service";
    serviceConfig = {
      Type      = "oneshot";
      User      = "lorcan";
      UMask     = "0007";
      ExecStart = pkgs.writeShellScript "embed-enrich-run" ''
        export OPENAI_API_KEY="$(cat ${config.age.secrets.openai-api-key.path})"
        export FINANCE_DUCKDB="/var/lib/foundry/lake/silver/finance.duckdb"
        exec ${foundryPkg}/bin/embed-enrich
      '';
      ExecStartPost = "${pkgs.curl}/bin/curl -fsS 'https://kuma.blue-apricots.com/api/push/V1hCTd4Enc6dKvBxUYNHBaViOcGQDmMk?status=up&msg=OK&ping='";
    };
  };

  systemd.timers.embed-enrich = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec         = "5min";
      OnUnitInactiveSec = "15min";
      Persistent        = true;
    };
  };

  # --- finance-dbt ----------------------------------------------------------
  systemd.services.finance-dbt = {
    description = "Foundry — dbt seed + incremental run";
    after       = [ "embed-enrich.service" ];
    unitConfig.OnFailure = "ntfy-alert@%n.service";
    serviceConfig = {
      Type      = "oneshot";
      User      = "lorcan";
      UMask     = "0007";
      ExecStartPre = pkgs.writeShellScript "finance-dbt-pre" ''
        for f in dim_budgets.csv dim_category_rules.csv dim_account_normalization.csv dim_holders.csv; do
          if [ -f /var/lib/foundry/seeds/$f ]; then
            install -m 0640 /var/lib/foundry/seeds/$f \
              /var/lib/foundry/dbt/seeds/$f
          fi
        done
        for f in dim_transfer_rules dim_category_overrides; do
          dest=/var/lib/foundry/dbt/seeds/$f.csv
          if [ ! -f $dest ]; then
            install -m 0640 ${foundryPkg}/share/foundry/seeds/$f.example.csv $dest
          fi
        done
      '';
      ExecStart = pkgs.writeShellScript "finance-dbt-run" ''
        export FINANCE_DUCKDB="/var/lib/foundry/lake/silver/finance.duckdb"
        export DBT_PROFILES_DIR="${foundryPkg}/share/foundry"
        export DBT_TARGET="prod"
        export DBT_LOG_PATH="/var/lib/foundry/dbt-state/logs"
        export DBT_TARGET_PATH="/var/lib/foundry/dbt-state/target"
        export DBT_PACKAGES_INSTALL_PATH="/var/lib/foundry/dbt-state/packages"
        mkdir -p "$DBT_LOG_PATH" "$DBT_TARGET_PATH" "$DBT_PACKAGES_INSTALL_PATH"
        cd /var/lib/foundry/dbt
        ${foundryPkg}/bin/foundry-dbt seed
        ${foundryPkg}/bin/foundry-dbt run
      '';
      ExecStartPost = "${pkgs.curl}/bin/curl -fsS 'https://kuma.blue-apricots.com/api/push/Dt12yqSm45yinjcd3UKIhKsv3KKDcs5f?status=up&msg=OK&ping='";
    };
  };
}
