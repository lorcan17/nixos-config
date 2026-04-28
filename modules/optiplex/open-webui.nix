{ domain, config, pkgs, ... }: {
  services.open-webui = {
    enable = true;
    host   = "127.0.0.1";
    port   = 8080;
    environment = {
      OLLAMA_BASE_URL = "http://localhost:11434";
      WEBUI_AUTH      = "False";
      # Writable site-packages for pip-installed function deps (e.g. claude-agent-sdk).
      # The Nix store is read-only so pip install must target a stateful directory.
      PYTHONPATH      = "/var/lib/open-webui/python-packages";
    };
    # Loaded after open-webui-env-prep.service writes it.
    environmentFile = "/run/open-webui-secrets/env";
  };

  # Separate oneshot that runs as root before open-webui starts.
  # systemd loads EnvironmentFile before ExecStartPre, so we can't use ExecStartPre
  # to create the file — it must exist before the service unit even starts.
  systemd.services.open-webui-env-prep = {
    description = "Write open-webui API key env file";
    before      = [ "open-webui.service" ];
    requiredBy  = [ "open-webui.service" ];
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

  # duckdb for finance_tools.py; claude-code for the claude-code pipe.
  systemd.services.open-webui.path = [ pkgs.duckdb pkgs.claude-code ];

  systemd.tmpfiles.rules = [
    # Writable site-packages for pip-installed OpenWebUI function deps.
    "d /var/lib/open-webui/python-packages 0755 open-webui open-webui -"
    # Prune claude-agent-pipe workdirs older than 7 days.
    "d /tmp/claude-agent-pipe 0755 open-webui open-webui -"
    "e /tmp/claude-agent-pipe 0755 open-webui open-webui 7d"
  ];

  # Install claude-agent-sdk into the writable PYTHONPATH dir.
  # Runs once; skips reinstall if already present at the right version.
  systemd.services.open-webui-python-deps = {
    description = "Install Python deps for OpenWebUI functions";
    before      = [ "open-webui.service" ];
    requiredBy  = [ "open-webui.service" ];
    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
      User            = "open-webui";
      ExecStart       = "${pkgs.uv}/bin/uv pip install \
        --target /var/lib/open-webui/python-packages \
        --system \
        'claude-agent-sdk>=0.1.60'";
    };
  };

  services.caddy.virtualHosts."chat.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:8080
  '';
}
