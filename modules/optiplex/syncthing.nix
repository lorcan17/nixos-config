{ domain, ... }:
{
  services.syncthing = {
    enable    = true;
    user      = "lorcan";
    dataDir   = "/var/lib/syncthing";
    configDir = "/var/lib/syncthing/.config/syncthing";

    # 22000/tcp (sync) + 21027/udp (discovery) opened on the firewall.
    openDefaultPorts = true;

    settings.folders."foundry-inbox-banking" = {
      path  = "/var/lib/foundry/lake/inbox/banking";
      id    = "foundry-inbox-banking";
      # Add partner device via the Syncthing Web UI after first boot,
      # then share this folder with them. Partner-facing instructions:
      #   1. Install Syncthing on their device
      #   2. Accept the device invite from http://optiplex:8384
      #   3. Accept the foundry-inbox-banking folder share
    };
  };

  # Syncthing Web UI — local access only via Tailscale/LAN.
  # To expose publicly: add a Caddy vhost pointing to localhost:8384.
  services.caddy.virtualHosts."sync.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:8384
  '';
}
