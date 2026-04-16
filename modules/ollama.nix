{ ... }:
{
  services.ollama = {
    enable = true;
    host   = "0.0.0.0"; # reachable from Mac via Tailscale
    port   = 11434;
  };

  networking.firewall.allowedTCPPorts = [ 11434 ];
}
