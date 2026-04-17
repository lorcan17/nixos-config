{ pkgs, ... }: {
  # Kokoro TTS via Docker (heavy Python/PyTorch deps; Docker is the pragmatic choice).
  # API is OpenAI-compatible: POST http://localhost:8880/v1/audio/speech
  systemd.services.kokoro = {
    description = "Kokoro TTS FastAPI server (Docker)";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "docker.service" "network-online.target" ];
    requires    = [ "docker.service" ];

    path = [ pkgs.docker ];

    serviceConfig = {
      Type       = "simple";
      Restart    = "on-failure";
      RestartSec = "15s";
      # Clean up any leftover container from a dirty shutdown
      ExecStartPre = "-${pkgs.docker}/bin/docker rm -f kokoro";
      ExecStop     = "${pkgs.docker}/bin/docker stop kokoro";
    };

    # Bind to all interfaces so Tailscale peers (Mac) can reach it directly.
    # No public firewall rule — Tailscale ACLs are the perimeter.
    script = ''
      exec docker run --rm \
        --name kokoro \
        -p 8880:8880 \
        ghcr.io/remsky/kokoro-fastapi-cpu:latest
    '';
  };
}
