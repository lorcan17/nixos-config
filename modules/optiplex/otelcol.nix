{ ... }:
{
  # OpenTelemetry Collector — unified telemetry receiver.
  #
  # Current job: receive OTLP from Python pipelines (when instrumented) and
  # expose a Prometheus metrics endpoint that prometheus.nix scrapes.
  #
  # Future: add more receivers (hostmetrics, filelog) or exporters as needed.
  # Python instrumentation prompt: see session notes / DECISIONS.md.
  services.opentelemetry-collector = {
    enable = true;
    settings = {
      receivers = {
        otlp = {
          protocols = {
            # Python pipelines push to these endpoints
            grpc.endpoint = "127.0.0.1:4317";
            http.endpoint = "127.0.0.1:4318";
          };
        };
      };

      processors = {
        batch = {};
      };

      exporters = {
        # Exposes received metrics for Prometheus to scrape at :8888
        prometheus = {
          endpoint = "127.0.0.1:8888";
        };
      };

      service = {
        pipelines = {
          metrics = {
            receivers  = [ "otlp" ];
            processors = [ "batch" ];
            exporters  = [ "prometheus" ];
          };
        };
      };
    };
  };
}
