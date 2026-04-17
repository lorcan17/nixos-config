{ pkgs, config, questrade-extract, finance-digest, ... }:
let
  extractEnv = pkgs.python3.withPackages (ps: [ ps.requests ]);
  digestEnv  = pkgs.python3.withPackages (ps: [ ps.requests ps.anthropic ]);
in {
  # agenix secrets readable by lorcan
  age.secrets.fmp-api-key.owner       = "lorcan";
  age.secrets.anthropic-api-key.owner = "lorcan";
  age.secrets.domain = {
    file  = ../../secrets/domain.age;
    mode  = "0400";
    owner = "lorcan";
  };

  # --- questrade-extract ---------------------------------------------------

  systemd.services.questrade-extract = {
    description = "Questrade daily snapshot extract";
    serviceConfig = {
      Type           = "oneshot";
      User           = "lorcan";
      ExecStart      = "${extractEnv}/bin/python3 -m questrade_extract.runner";
      StateDirectory = "questrade-extract";
      Environment    = [
        "PYTHONPATH=${questrade-extract}/src"
        "STATE_DIRECTORY=/var/lib/questrade-extract"
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
      ExecStart = pkgs.writeShellScript "finance-digest-run" ''
        export NTFY_URL="https://ntfy.$(cat ${config.age.secrets.domain.path})/finance"
        export PYTHONPATH="${finance-digest}/src"
        export QUESTRADE_DB_PATH="/var/lib/questrade-extract/questrade.db"
        exec ${digestEnv}/bin/python3 -m finance_digest.runner
      '';
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
