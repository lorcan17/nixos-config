{ pkgs, config, domain, questrade-extract, finance-digest, ... }:
let
  otelPkgs   = ps: [ ps.opentelemetry-api ps.opentelemetry-sdk ps.opentelemetry-exporter-otlp-proto-grpc ];
  extractEnv = pkgs.python3.withPackages (ps: [ ps.requests ] ++ otelPkgs ps);
  digestEnv  = pkgs.python3.withPackages (ps: [ ps.requests ps.anthropic ] ++ otelPkgs ps);
in {
  # agenix secrets readable by lorcan
  # domain secret is declared in alerts.nix; referenced here via config.age.secrets.domain.path
  age.secrets.fmp-api-key.owner       = "lorcan";
  age.secrets.anthropic-api-key.owner = "lorcan";

  # --- questrade-extract ---------------------------------------------------

  systemd.services.questrade-extract = {
    description = "Questrade daily snapshot extract";
    serviceConfig = {
      Type           = "oneshot";
      User           = "lorcan";
      OnFailure      = "ntfy-alert@%n.service";
      ExecStart      = "${extractEnv}/bin/python3 -m questrade_extract.runner";
      ExecStartPost  = "${pkgs.curl}/bin/curl -fsS 'https://kuma.blue-apricots.com/api/push/RZBVNAMPW1ZXKA8cy5JRay3EIvhZkpAq?status=up&msg=OK&ping='";
      StateDirectory = "questrade-extract";
      Environment    = [
        "PYTHONPATH=${questrade-extract}/src"
        "STATE_DIRECTORY=/var/lib/questrade-extract"
        "OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4317"
      ];
    };
  };

  systemd.timers.questrade-extract = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Mon-Fri 16:30:00";
      TimeZone   = "America/Vancouver";
      Persistent = true;
    };
  };

  # --- finance-digest -------------------------------------------------------
  # config.py reads FMP_API_KEY and ANTHROPIC_API_KEY from /run/agenix/ directly
  # when env vars are not set.

  systemd.services.finance-digest = {
    description = "Daily portfolio digest via Claude + ntfy";
    after       = [ "questrade-extract.service" ];
    serviceConfig = {
      Type      = "oneshot";
      User      = "lorcan";
      OnFailure = "ntfy-alert@%n.service";
      ExecStart = pkgs.writeShellScript "finance-digest-run" ''
        export NTFY_URL="https://ntfy.${domain}/finance"
        export PYTHONPATH="${finance-digest}/src"
        export QUESTRADE_DB_PATH="/var/lib/questrade-extract/questrade.db"
        export OTEL_EXPORTER_OTLP_ENDPOINT="http://localhost:4317"
        exec ${digestEnv}/bin/python3 -m finance_digest.runner
      '';
      ExecStartPost = "${pkgs.curl}/bin/curl -fsS 'https://kuma.blue-apricots.com/api/push/8k5B7mYQthhIYYCKlCI0GOk5WVMOYyga?status=up&msg=OK&ping='";
    };
  };

  systemd.timers.finance-digest = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Mon-Fri 17:00:00";
      TimeZone   = "America/Vancouver";
      Persistent = true;
    };
  };
}
