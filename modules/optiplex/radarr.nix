{ domain, ... }: {
  services.radarr.enable = true; # port 7878

  services.caddy.virtualHosts."radarr.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:7878
  '';
}
