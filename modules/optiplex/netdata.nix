{ domain, ... }: {
  services.netdata.enable = true;

  services.caddy.virtualHosts."monitor.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:19999
  '';
}
