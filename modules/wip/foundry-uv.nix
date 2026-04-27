{ pkgs, config, finance-lake, ... }:
#
# Spike: uv-based variant of embed-enrich. Sits alongside the current
# foundry.nix (not imported until promoted out of wip/). Compare ergonomics
# and rebuild speed against the buildPythonPackage path before migrating
# the rest of the foundry services.
#
# Open questions to resolve before promoting:
#
# 1. Source layout for statement-extract — DECIDED: drop editable, use a
#    pinned git source in finance-lake's pyproject.toml. Same source on Mac
#    and prod; cost is a commit/push/uv-lock cycle on every statement-extract
#    change. Trade accepted as the price for a uniform, simple build.
#    Pre-migration step: edit finance-lake/pyproject.toml dependencies to
#    `statement-extract @ git+https://github.com/lorcan17/statement-extract@<rev>`
#    (or the [tool.uv.sources] equivalent).
#
# 2. uv cache + venv ownership.
#    Cache lives under XDG_CACHE_HOME (set per service). Venv lives under
#    a StateDirectory so it survives across rebuilds and only re-syncs
#    when uv.lock changes. Both must be writable by the service user.
#
# 3. Determinism guarantee.
#    `uv sync --frozen` refuses to update the lock — anything not in
#    uv.lock fails the sync. PyPI itself can still serve a different wheel
#    for the same hash if a release is yanked, but uv.lock pins by hash so
#    this is detected, not silently swapped.

let
  # Stable parent dir on the host where finance-lake source lives. uv reads
  # pyproject.toml + uv.lock from here. This dir is symlinked into the Nix
  # store path, so it's read-only — uv writes its venv elsewhere.
  src = finance-lake;
in {
  # `uv sync` creates and populates a venv from uv.lock. The venv is
  # rebuilt only when uv.lock changes (uv detects this via lockfile hash).
  systemd.services.embed-enrich-uv = {
    description = "Foundry — enrich bronze rows (uv variant)";
    after       = [ "network-online.target" ];
    wants       = [ "network-online.target" ];

    unitConfig.OnFailure = "ntfy-alert@%n.service";

    serviceConfig = {
      Type           = "oneshot";
      User           = "lorcan";
      StateDirectory = "finance-lake-uv";  # /var/lib/finance-lake-uv — venv + uv cache
      Environment = [
        "UV_CACHE_DIR=/var/lib/finance-lake-uv/cache"
        "UV_PROJECT_ENVIRONMENT=/var/lib/finance-lake-uv/.venv"
        "OPENAI_API_KEY_FILE=${config.age.secrets.openai-api-key.path}"
        "FINANCE_DUCKDB=/var/lib/finance-lake/finance.duckdb"
      ];

      # Stage source into a writable working dir so uv can resolve relative
      # paths from pyproject.toml (esp. the editable statement-extract).
      # See open question (1) — this current copy assumes statement-extract
      # is *not* needed at runtime, which is wrong; will fail until resolved.
      ExecStartPre = pkgs.writeShellScript "embed-enrich-uv-pre" ''
        set -euo pipefail
        rm -rf $STATE_DIRECTORY/src
        cp -r ${src} $STATE_DIRECTORY/src
        chmod -R u+w $STATE_DIRECTORY/src
        cd $STATE_DIRECTORY/src
        ${pkgs.uv}/bin/uv sync --frozen --no-dev
      '';

      ExecStart = pkgs.writeShellScript "embed-enrich-uv-run" ''
        set -euo pipefail
        export OPENAI_API_KEY="$(cat $OPENAI_API_KEY_FILE)"
        cd $STATE_DIRECTORY/src
        exec ${pkgs.uv}/bin/uv run --frozen --no-dev python -m embed_enrich
      '';
    };
  };

  # No timer in the spike — invoke manually to test:
  #   sudo systemctl start embed-enrich-uv.service
  # Compare wall-time + log noise against the buildPythonPackage variant.
}
