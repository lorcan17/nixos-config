{ pkgs, domain, ... }:
{
  # Template service: OnFailure = "ntfy-alert@%n.service" in any unit sends
  # an urgent ntfy push to the `alerts` topic with the failed unit name.
  #
  # Add to a service:
  #   systemd.services.<name>.serviceConfig.OnFailure = "ntfy-alert@%n.service";
  systemd.services."ntfy-alert@" = {
    description = "ntfy alert for failed unit %i";
    serviceConfig = {
      Type = "oneshot";
      User = "lorcan";
      ExecStart = pkgs.writeShellScript "ntfy-alert" ''
        ${pkgs.curl}/bin/curl -s \
          -H "Title: ❌ %i failed" \
          -H "Priority: urgent" \
          -H "Tags: warning,optiplex" \
          -d "systemd unit %i failed on optiplex — check: journalctl -u %i -n 50" \
          "https://ntfy.${domain}/alerts"
      '';
    };
  };
}
