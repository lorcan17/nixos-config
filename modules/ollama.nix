{ ... }:
{
  services.ollama = {
    enable        = true;
    listenAddress = "0.0.0.0:11434"; # reachable from Mac via Tailscale
    acceleration  = null;            # CPU only — set "cuda" or "rocm" if you add a GPU
  };

  networking.firewall.allowedTCPPorts = [ 11434 ];
}
