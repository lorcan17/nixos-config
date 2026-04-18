{ ... }: {
  services.netdata.enable = true;

  services.caddy.virtualHosts."monitor.{$DOMAIN}".extraConfig = ''
    tls {
      dns cloudflare {$CF_API_TOKEN}
    }
    reverse_proxy localhost:19999
  '';
}
