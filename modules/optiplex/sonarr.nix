{ domain, ... }: {
  services.sonarr.enable = true; # port 8989

  services.caddy.virtualHosts."sonarr.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:8989
  '';
}
