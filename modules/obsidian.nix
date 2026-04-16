{ ... }:
{
  # OptiPlex: sync the Obsidian vault via Syncthing so OpenClaw can read PARA notes.
  # On Mac, Obsidian is installed as a cask via mac-homebrew.nix.
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
