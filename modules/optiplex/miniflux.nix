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
    # FocusReader sends FreshRSS-style paths — rewrite to Miniflux equivalents
    rewrite /v1/api/greader.php/* /{path}
    reverse_proxy localhost:8084
  '';
}
