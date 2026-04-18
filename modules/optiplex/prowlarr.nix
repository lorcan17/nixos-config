{ domain, ... }: {
  services.prowlarr.enable = true; # port 9696

  services.caddy.virtualHosts."prowlarr.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:9696
  '';
}
