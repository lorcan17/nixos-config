{ ... }:
{
  # OptiPlex: sync files (e.g., Obsidian vaults, documents) via Syncthing.
  # This provides the "transfer" layer between devices.
  services.syncthing = {
    enable   = true;
    user     = "lorcan";
    dataDir  = "/home/lorcan";
    settings = {
      folders."obsidian-vault" = {
        path = "/home/lorcan/obsidian";
        # Add device IDs via the Syncthing web UI at http://optiplex:8384
      };
    };
  };

  networking.firewall.allowedTCPPorts = [ 8384 22000 ];
  networking.firewall.allowedUDPPorts = [ 22000 21027 ];
}
