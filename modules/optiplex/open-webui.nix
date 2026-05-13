{ domain, config, pkgs, ... }: {

  virtualisation.oci-containers.containers.open-webui = {
    image   = "ghcr.io/open-webui/open-webui:v0.6.5";
    volumes = [
      "/var/lib/open-webui:/app/backend/data"
      # read-only mount at the path finance_tools.py expects via FINANCE_DUCKDB default
      "/var/lib/finance-lake/finance.duckdb:/var/lib/finance-lake/finance.duckdb:ro"
    ];
    environment = {
      OLLAMA_BASE_URL = "http://127.0.0.1:11434";
      WEBUI_AUTH      = "false";
    };
    # API keys written at boot by open-webui-env-prep.service
    environmentFiles = [ "/run/open-webui-secrets/env" ];
    # Host networking: Ollama on localhost works; Open-WebUI binds to host port 8080
    extraOptions = [ "--network=host" ];
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
    reverse_proxy localhost:8080
  '';
}
