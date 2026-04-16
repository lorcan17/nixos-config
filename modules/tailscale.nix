{ config, ... }:
{
  # OptiPlex: Tailscale systemd service
  # On Mac, Tailscale is installed as a cask via mac-homebrew.nix
  services.tailscale = {
    enable      = true;
    authKeyFile = config.age.secrets.tailscale-authkey.path;
    # extraUpFlags = [ "--ssh" ];  # enable Tailscale SSH when ready
  };

  networking.firewall = {
    trustedInterfaces = [ "tailscale0" ];
    allowedUDPPorts   = [ 41641 ];
  };
}
