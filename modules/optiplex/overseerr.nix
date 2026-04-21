{ domain, ... }: {
  services.jellyseerr.enable = true; # port 5055

  services.caddy.virtualHosts."seer.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:5055
  '';
}
