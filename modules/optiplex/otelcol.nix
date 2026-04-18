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
        # :8888 is otelcol's own internal telemetry; use :8889 for the exporter
        prometheus = {
          endpoint = "127.0.0.1:8889";
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
