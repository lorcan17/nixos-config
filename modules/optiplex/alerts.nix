{ pkgs, domain, ... }:
{
  # Template service: OnFailure = "ntfy-alert@%n.service" in any unit sends
  # an urgent ntfy push to the `alerts` topic with the failed unit name.
  #
  # Add to a service:
  #   systemd.services.<name>.unitConfig.OnFailure = "ntfy-alert@%n.service";
  #
  # NOTE: must be unitConfig (not serviceConfig). systemd's OnFailure lives in
  # the [Unit] section; under [Service] it's silently ignored.
  systemd.services."ntfy-alert@" = {
    description = "ntfy alert for failed unit %i";
    # Rate-limit: at most one ntfy push per failing unit per hour.
    # systemd applies StartLimit per-instance, so each failing unit gets its
    # own bucket — a flapping timer can't drown out a separate real failure.
    startLimitIntervalSec = 3600;
    startLimitBurst = 1;
    serviceConfig = {
      Type = "oneshot";
      User = "lorcan";
      # systemd's %i specifier only expands on the ExecStart= line itself,
      # not inside files referenced from it. Pass the unit name as $1.
      ExecStart = ''${pkgs.writeShellScript "ntfy-alert" ''
        UNIT="$1"

        EXIT_CODE=$(${pkgs.systemd}/bin/systemctl show --property=ExecMainStatus --value "$UNIT" 2>/dev/null || echo "unknown")
        LAST_LINES=$(${pkgs.systemd}/bin/journalctl -u "$UNIT" -n 5 --no-pager 2>/dev/null | tail -3)

        BODY="❌ $UNIT failed on optiplex

        Exit code: $EXIT_CODE

        Recent logs:
        $LAST_LINES"

        ${pkgs.curl}/bin/curl -s \
          -H "Title: ❌ $UNIT failed" \
          -H "Priority: urgent" \
          -H "Tags: warning,optiplex" \
          -d "$BODY" \
          "https://ntfy.${domain}/alerts"
      ''} %i'';
    };
  };
}
