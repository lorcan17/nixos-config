{ ... }:
{
  services.restic.backups.daily = {
    initialize = true;
    paths      = [
      "/home/lorcan/nix-config"
      "/home/lorcan/obsidian"
      "/home/lorcan/openclaw"
      "/data/downloads"
    ];
    exclude = [ "node_modules" ".cache" "*.tmp" ];

    # REPLACE: choose one
    # Local USB:  repository = "/mnt/backup/restic";
    # Backblaze:  repository = "b2:lorcan-backup";
    #             environmentFile = config.age.secrets.restic-b2.path;
    repository = "/mnt/backup/restic"; # REPLACE

    timerConfig = { OnCalendar = "daily"; Persistent = true; };
  };
}
