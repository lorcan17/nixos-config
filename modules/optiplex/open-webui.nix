{ domain, config, pkgs, ... }: {

  virtualisation.oci-containers.containers.open-webui = {
    image   = "ghcr.io/open-webui/open-webui:v0.9.5";
    volumes = [
      "/var/lib/open-webui:/app/backend/data"
      # persistent pip packages dir — populated by open-webui-pip-deps before start
      "/var/lib/open-webui/site-packages:/extra-packages"
      # read-only mount at the path finance_tools.py expects via FINANCE_DUCKDB default
      "/var/lib/finance-lake/finance.duckdb:/var/lib/finance-lake/finance.duckdb:ro"
    ];
    environment = {
      OLLAMA_BASE_URL = "http://127.0.0.1:11434";
      WEBUI_AUTH      = "false";
      PYTHONPATH      = "/extra-packages";
    };
    # API keys written at boot by open-webui-env-prep.service
    environmentFiles = [ "/run/open-webui-secrets/env" ];
    # Host networking: Ollama on localhost works; Open-WebUI binds to host port 8080
    extraOptions = [ "--network=host" ];
  };

  # Install extra Python packages (duckdb) into a persistent volume-mounted dir.
  # Uses the same image so Python version matches; skips if already installed.
  # Must run before the container so PYTHONPATH picks them up at startup.
  systemd.services.open-webui-pip-deps = {
    description = "Install extra Python packages for open-webui (duckdb)";
    before      = [ "podman-open-webui.service" ];
    requiredBy  = [ "podman-open-webui.service" ];
    path        = [ pkgs.podman ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "owui-pip-deps" ''
        mkdir -p /var/lib/open-webui/site-packages
        if [ ! -d /var/lib/open-webui/site-packages/duckdb ]; then
          podman run --rm \
            -v /var/lib/open-webui/site-packages:/extra-packages \
            ghcr.io/open-webui/open-webui:v0.9.5 \
            pip install --target /extra-packages --quiet duckdb
        fi
      '';
    };
  };

  # Oneshot that writes agenix secrets to an env file before the container starts.
  # EnvironmentFile must exist before the container unit starts, so this must run first.
  systemd.services.open-webui-env-prep = {
    description = "Write open-webui API key env file";
    before      = [ "podman-open-webui.service" ];
    requiredBy  = [ "podman-open-webui.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
      ExecStart = "+${pkgs.writeShellScript "owui-env-prep" ''
        install -d -m 700 /run/open-webui-secrets
        {
          printf 'ANTHROPIC_API_KEY=%s\n'        "$(cat ${config.age.secrets.anthropic-api-key.path})"
          printf 'OPENROUTER_API_KEY=%s\n'       "$(cat ${config.age.secrets.open-router-api-key.path})"
          printf 'CLAUDE_CODE_OAUTH_TOKEN=%s\n'  "$(cat ${config.age.secrets.claude-code-oauth-token.path})"
        } > /run/open-webui-secrets/env
        chmod 600 /run/open-webui-secrets/env
      ''}";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/lib/open-webui 0750 root root -"
  ];

  services.caddy.virtualHosts."chat.${domain}".extraConfig = ''
    import cloudflare_tls
    header Content-Security-Policy "default-src 'self' 'unsafe-inline' 'unsafe-eval' data: blob:; script-src 'self' 'unsafe-inline' 'unsafe-eval' https://cdn.jsdelivr.net https://cdnjs.cloudflare.com; style-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net https://cdnjs.cloudflare.com; img-src 'self' data: blob: https:; connect-src 'self' wss: https:; frame-src 'self' blob: data:"
    reverse_proxy localhost:8080
  '';
}
