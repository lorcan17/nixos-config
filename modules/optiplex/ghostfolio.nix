{ config, pkgs, domain, ... }:
let
  composeFile = pkgs.writeText "ghostfolio-compose.yml" ''
    version: "3.8"

    services:
      postgres:
        image: postgres:15-alpine
        environment:
          POSTGRES_DB: ghostfolio
          POSTGRES_USER: ghostfolio
          POSTGRES_PASSWORD: ghostfolio-internal
        volumes:
          - postgres-data:/var/lib/postgresql/data
        healthcheck:
          test: ["CMD-SHELL", "pg_isready -U ghostfolio -d ghostfolio"]
          interval: 10s
          timeout: 5s
          retries: 5
        restart: unless-stopped

      redis:
        image: redis:7-alpine
        healthcheck:
          test: ["CMD", "redis-cli", "ping"]
          interval: 10s
          timeout: 5s
          retries: 5
        restart: unless-stopped

      ghostfolio:
        image: ghostfolio/ghostfolio:latest
        ports:
          - "127.0.0.1:3333:3333"
        environment:
          DATABASE_URL: "postgresql://ghostfolio:ghostfolio-internal@postgres:5432/ghostfolio?sslmode=prefer"
          REDIS_HOST: redis
          REDIS_PORT: "6379"
          ACCESS_TOKEN_SALT: tailscale-only-no-public-exposure
          JWT_SECRET_KEY: tailscale-only-no-public-exposure
          API_KEY_FINANCIAL_MODELING_PREP: ''${FMP_API_KEY}
          NODE_ENV: production
        depends_on:
          postgres:
            condition: service_healthy
          redis:
            condition: service_healthy
        restart: unless-stopped

    volumes:
      postgres-data:
  '';
in {
  systemd.services.ghostfolio = {
    description = "Ghostfolio portfolio tracker (Docker Compose)";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "docker.service" "network-online.target" ];
    requires    = [ "docker.service" ];

    path = [ pkgs.docker-compose ];

    serviceConfig = {
      Type       = "simple";
      Restart    = "on-failure";
      RestartSec = "10s";
    };

    # fmp-api-key is a raw value file, not KEY=VALUE format
    script = ''
      export FMP_API_KEY=$(< ${config.age.secrets.fmp-api-key.path})
      exec docker-compose -f ${composeFile} --project-name ghostfolio up --remove-orphans
    '';

    preStop = ''
      docker-compose -f ${composeFile} --project-name ghostfolio down
    '';
  };

  services.caddy.virtualHosts."ghostfolio.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:3333
  '';
}
