{ domain, ... }:
{
  # Uptime Kuma — HTTP uptime monitoring + push heartbeat monitors.
  #
  # Configuration is UI-only (no declarative config supported).
  # After first rebuild, visit https://kuma.DOMAIN and set up:
  #
  # HTTP monitors (one per subdomain):
  #   ntfy, chat, abs, ghostfolio, monitor, grafana, prometheus
  #
  # Push heartbeat monitors (pipelines phone home on success):
  #   questrade-extract  — expect ping every 24h Mon-Fri
  #   finance-digest     — expect ping every 24h Mon-Fri
  #   audiobook-pipeline — expect ping per run (on demand)
  #
  # ntfy notification: Settings → Notifications → ntfy → https://ntfy.DOMAIN/alerts
  services.uptime-kuma = {
    enable = true;
    settings.HOST = "127.0.0.1";
    settings.PORT = "3001";
  };

  services.caddy.virtualHosts."kuma.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:3001
  '';
}
