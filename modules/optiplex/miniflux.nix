{ config, domain, ... }:
{
  services.miniflux = {
    enable = true;
    createDatabaseLocally = true;
    adminCredentialsFile = config.age.secrets.miniflux-admin-credentials.path;
    config = {
      LISTEN_ADDR = "localhost:8084";
      BASE_URL    = "https://rss.${domain}";
    };
  };

  services.caddy.virtualHosts."rss.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:8084
  '';
}
