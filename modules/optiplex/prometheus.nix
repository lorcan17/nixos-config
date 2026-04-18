{ domain, ... }:
{
  services.prometheus = {
    enable = true;
    port   = 9090;
    listenAddress = "127.0.0.1";

    exporters.node = {
      enable = true;
      port   = 9100;
      # systemd collector exposes per-unit state — lets Grafana alert on failed services
      enabledCollectors = [ "systemd" "processes" ];
    };

    scrapeConfigs = [
      {
        job_name = "node";
        static_configs = [{ targets = [ "localhost:9100" ]; }];
      }
      {
        # Netdata has a native Prometheus endpoint; no exporter needed
        job_name     = "netdata";
        metrics_path = "/api/v1/allmetrics";
        params        = { format = [ "prometheus_all_hosts" ]; };
        static_configs = [{ targets = [ "localhost:19999" ]; }];
      }
      {
        # OTEL Collector exposes its received metrics on :8888
        job_name = "otel-collector";
        static_configs = [{ targets = [ "localhost:8888" ]; }];
      }
    ];
  };

  services.caddy.virtualHosts."prometheus.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:9090
  '';
}
