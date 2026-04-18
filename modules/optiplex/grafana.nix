{ domain, ... }:
{
  services.grafana = {
    enable = true;

    settings = {
      server = {
        http_addr = "127.0.0.1";
        http_port = 3000;
        domain    = "grafana.${domain}";
        root_url  = "https://grafana.${domain}";
      };

      # Tailscale is the perimeter — no login required on the tailnet
      "auth.anonymous" = {
        enabled  = true;
        org_role = "Admin";
      };
    };

    provision = {
      enable = true;

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
