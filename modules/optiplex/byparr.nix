{ pkgs, ... }: {
  # Byparr — lightweight FlareSolverr-compatible Cloudflare bypass proxy.
  # Prowlarr points at http://localhost:8191 under Settings → Indexers → FlareSolverr.
  systemd.services.byparr = {
    description = "Byparr Cloudflare bypass proxy (Docker)";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "docker.service" "network-online.target" ];
    requires    = [ "docker.service" ];

    path = [ pkgs.docker ];

    serviceConfig = {
      Type       = "simple";
      Restart    = "on-failure";
      RestartSec = "15s";
      ExecStartPre = "-${pkgs.docker}/bin/docker rm -f byparr";
      ExecStop     = "${pkgs.docker}/bin/docker stop byparr";
    };

    script = ''
      exec docker run --rm \
        --name byparr \
        -p 127.0.0.1:8191:8191 \
        ghcr.io/thephaseless/byparr:latest
    '';
  };
}
