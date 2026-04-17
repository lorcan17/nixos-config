{ config, ... }:
{
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url        = "https://ntfy.{$DOMAIN}";
      listen-http     = ":2586";
      behind-proxy    = true;
      auth-default-access = "allow-all";
    };
  };

  # Caddy vhost — proxies ntfy.{$DOMAIN} → localhost:2586
  services.caddy.virtualHosts."ntfy.{$DOMAIN}".extraConfig = ''
    tls internal
    reverse_proxy localhost:2586
  '';
}
