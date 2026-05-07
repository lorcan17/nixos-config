{ pkgs, ... }:

{
  # Reboot weekly on Sunday at 03:00 to apply kernel/firmware updates and clear uptime.
  # Finance pipelines run weekdays only, so Sunday 03:00 is a safe window.
  systemd.timers.weekly-reboot = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun 03:00";
      Persistent = true;
    };
  };

  systemd.services.weekly-reboot = {
    description = "Weekly scheduled reboot";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl reboot";
    };
  };

  # Cap journal size — Ollama + pipeline logs accumulate fast.
  services.journald.extraConfig = "SystemMaxUse=2G";

  # SMART monitoring — alerts before a drive fails silently.
  services.smartd.enable = true;
}
