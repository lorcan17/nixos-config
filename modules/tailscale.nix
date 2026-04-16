{ ... }:
{
  # OptiPlex: Tailscale systemd service
  # On Mac, Tailscale is installed as a cask via mac-homebrew.nix
  services.tailscale.enable = true;

  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts   = [ 41641 ];
  };
}
