{ config, domain, pkgs, ... }:
{
  age.secrets.grafana-secret-key = {
    file  = ../../secrets/grafana-secret-key.age;
    mode  = "0400";
    owner = "grafana";
  };

  # Declarative Node Exporter Full dashboard (#1860)
  systemd.tmpfiles.rules = [
    "d /var/lib/grafana/dashboards 0755 grafana grafana -"
  ];

  systemd.services.grafana-dashboard-node-exporter = {
    description = "Download Node Exporter Full dashboard for Grafana";
    wantedBy    = [ "grafana.service" ];
    before      = [ "grafana.service" ];
    script      = ''
      if [ ! -f /var/lib/grafana/dashboards/node-exporter-full.json ]; then
        ${pkgs.curl}/bin/curl -s https://grafana.com/api/dashboards/1860/revisions/37/download | \
        ${pkgs.gnused}/bin/sed 's/\${DS_PROMETHEUS}/prometheus/g' > /var/lib/grafana/dashboards/node-exporter-full.json
        chown grafana:grafana /var/lib/grafana/dashboards/node-exporter-full.json
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      User = "root";
    };
  };

  services.grafana = {
    enable = true;

    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3000;
        domain    = "grafana.${domain}";
        root_url  = "https://grafana.${domain}";
      };

      security.secret_key = "$__file{${config.age.secrets.grafana-secret-key.path}}";

      # Tailscale is the perimeter — no login required on the tailnet
      "auth.anonymous" = {
        enabled  = true;
        org_role = "Admin";
      };
    };

    provision = {
      enable = true;

      dashboards.settings = {
        apiVersion = 1;
        providers = [{
          name = "node-exporter";
          options.path = "/var/lib/grafana/dashboards";
        }];
      };

      datasources.settings = {
        apiVersion = 1;
        datasources = [{
          name      = "Prometheus";
          type      = "prometheus";
          uid       = "prometheus";
          url       = "http://localhost:9090";
          isDefault = true;
        }];
      };

      alerting = {
        # ntfy webhook contact point — all alerts route here by default
        contactPoints.settings = {
          apiVersion = 1;
          contactPoints = [{
            orgId = 1;
            name  = "ntfy";
            receivers = [{
              uid  = "ntfy-alerts";
              type = "webhook";
              settings = {
                url        = "https://ntfy.${domain}/alerts";
                httpMethod = "POST";
                # Mapping Grafana fields to ntfy headers for a clean push notification
                headerName1  = "Title";
                headerValue1 = "{{ .GroupLabels.alertname }}";
                headerName2  = "Priority";
                headerValue2 = "urgent";
                headerName3  = "Tags";
                headerValue3 = "warning,optiplex";
              };
              disableResolveMessage = false;
            }];
          }];
        };

        # Route all alerts to ntfy by default
        policies.settings = {
          apiVersion = 1;
          policies = [{
            orgId    = 1;
            receiver = "ntfy";
          }];
        };

        # Disk > 85% alert — the most important homelab alert given audiobook pipeline
        rules.settings = {
          apiVersion = 1;
          groups = [{
            orgId    = 1;
            name     = "homelab";
            folder   = "Homelab";
            interval = "5m";
            rules = [
              {
                uid       = "disk-high";
                title     = "Disk usage > 85%";
                annotations = {
                  summary     = "Disk usage on optiplex is high: {{ $values.A.Value | printf \"%.2f\" }}%";
                  description = "The root partition is filling up. Check for large downloads or logs.";
                };
                condition = "C";
                data = [
                  {
                    refId = "A";
                    relativeTimeRange = { from = 300; to = 0; };
                    datasourceUid = "prometheus";
                    model = {
                      expr        = "(1 - node_filesystem_avail_bytes{mountpoint=\"/\"} / node_filesystem_size_bytes{mountpoint=\"/\"}) * 100";
                      instant     = true;
                      refId       = "A";
                    };
                  }
                  {
                    refId = "C";
                    relativeTimeRange = { from = 0; to = 0; };
                    datasourceUid = "__expr__";
                    model = {
                      type       = "threshold";
                      expression = "A";
                      refId      = "C";
                      conditions = [{
                        evaluator = { type = "gt"; params = [ 85 ]; };
                        operator  = { type = "and"; };
                        query     = { params = [ "A" ]; };
                        reducer   = { type = "last"; params = []; };
                        type      = "query";
                      }];
                    };
                  }
                ];
                noDataState  = "OK";
                execErrState = "Error";
                for          = "5m";
                isPaused     = false;
              }
              {
                uid       = "cpu-high";
                title     = "CPU usage > 90%";
                condition = "C";
                data = [
                  {
                    refId = "A";
                    relativeTimeRange = { from = 600; to = 0; };
                    datasourceUid = "prometheus";
                    model = {
                      expr  = "100 - (avg(rate(node_cpu_seconds_total{mode=\"idle\"}[5m])) * 100)";
                      instant = true;
                      refId = "A";
                    };
                  }
                  {
                    refId = "C";
                    relativeTimeRange = { from = 0; to = 0; };
                    datasourceUid = "__expr__";
                    model = {
                      type       = "threshold";
                      expression = "A";
                      refId      = "C";
                      conditions = [{
                        evaluator = { type = "gt"; params = [ 90 ]; };
                        operator  = { type = "and"; };
                        query     = { params = [ "A" ]; };
                        reducer   = { type = "last"; params = []; };
                        type      = "query";
                      }];
                    };
                  }
                ];
                noDataState  = "OK";
                execErrState = "Error";
                # sustained high CPU for 10m before alerting to avoid spikes
                for          = "10m";
                isPaused     = false;
              }
              {
                uid       = "memory-high";
                title     = "Memory usage > 85%";
                annotations = {
                  summary     = "Memory usage on optiplex is high: {{ $values.A.Value | printf \"%.2f\" }}%";
                  description = "Low memory available. This can cause system instability or OOM kills.";
                };
                condition = "C";
                data = [
                  {
                    refId = "A";
                    relativeTimeRange = { from = 300; to = 0; };
                    datasourceUid = "prometheus";
                    model = {
                      expr  = "(1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100";
                      instant = true;
                      refId = "A";
                    };
                  }
                  {
                    refId = "C";
                    relativeTimeRange = { from = 0; to = 0; };
                    datasourceUid = "__expr__";
                    model = {
                      type       = "threshold";
                      expression = "A";
                      refId      = "C";
                      conditions = [{
                        evaluator = { type = "gt"; params = [ 85 ]; };
                        operator  = { type = "and"; };
                        query     = { params = [ "A" ]; };
                        reducer   = { type = "last"; params = []; };
                        type      = "query";
                      }];
                    };
                  }
                ];
                noDataState  = "OK";
                execErrState = "Error";
                for          = "5m";
                isPaused     = false;
              }
            ];
          }];
        };
      };
    };
  };

  services.caddy.virtualHosts."grafana.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:3000
  '';
}

