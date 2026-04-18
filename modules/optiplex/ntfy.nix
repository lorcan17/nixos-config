{ config, ... }:
{
  services.ntfy-sh = {
    enable = true;
    settings = {
      listen-http         = ":2586";
      behind-proxy        = true;
      auth-default-access = "allow-all";
    };
  };

  # Caddy vhost — proxies ntfy.{$DOMAIN} → localhost:2586
  services.caddy.virtualHosts."ntfy.{$DOMAIN}".extraConfig = ''
    tls {
      dns cloudflare {$CF_API_TOKEN}
    }
    reverse_proxy localhost:2586
  '';
}
