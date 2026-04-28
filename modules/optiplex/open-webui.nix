{ domain, config, pkgs, ... }: {
  services.open-webui = {
    enable = true;
    host   = "127.0.0.1";
    port   = 8080;
    environment = {
      OLLAMA_BASE_URL = "http://localhost:11434";
      WEBUI_AUTH      = "False";
      # Redirect pip installs to a writable directory inside StateDirectory.
      # PIP_TARGET makes `pip install` write there; PYTHONPATH makes it importable.
      # Both ExecStartPre and the app process share the same filesystem namespace
      # (StateDirectory), so this path is consistent across both.
      PIP_TARGET  = "/var/lib/open-webui/python-packages";
      PYTHONPATH  = "/var/lib/open-webui/python-packages";
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
    # Prune claude-agent-pipe workdirs older than 7 days.
    "d /tmp/claude-agent-pipe 0755 root root -"
    "e /tmp/claude-agent-pipe 0755 root root 7d"
  ];

  # Install claude-agent-sdk inside the service's own filesystem namespace.
  # open-webui uses StateDirectory + PrivateTmp, so root-owned oneshots can't
  # write into the path the service actually sees — must run as ExecStartPre
  # under the service's own DynamicUser context.
  # --no-deps: pydantic/httpx/anyio are already in OpenWebUI's Nix Python env;
  # reinstalling them shadows the Nix versions and breaks pydantic-core C ext.
  systemd.services.open-webui.serviceConfig.ExecStartPre =
    "+${pkgs.writeShellScript "owui-pip-deps" ''
      ${pkgs.python3Packages.pip}/bin/pip install \
        --target /var/lib/open-webui/python-packages \
        --no-deps \
        --quiet \
        'claude-agent-sdk>=0.1.60'
    ''}";

  services.caddy.virtualHosts."chat.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:8080
  '';
}
