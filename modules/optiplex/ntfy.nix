{ domain, ... }:
{
  services.ntfy-sh = {
    enable = true;
    settings = {
      base-url            = "https://ntfy.${domain}";
      listen-http         = ":2586";
      behind-proxy        = true;
      auth-default-access = "read-write";
    };
  };

  services.caddy.virtualHosts."ntfy.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:2586
  '';
}
