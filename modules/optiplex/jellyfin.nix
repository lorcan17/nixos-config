{ domain, ... }: {
  services.jellyfin = {
    enable   = true;
    openFirewall = false; # behind Caddy; no direct port exposure needed
  };

  services.caddy.virtualHosts."media.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:8096
  '';
}
