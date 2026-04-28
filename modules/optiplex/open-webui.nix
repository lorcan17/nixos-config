{ domain, config, pkgs, ... }: {
  services.open-webui = {
    enable = true;
    host   = "127.0.0.1";
    port   = 8080;
    environment = {
      OLLAMA_BASE_URL = "http://localhost:11434";
      WEBUI_AUTH     = "False";
      # duckdb on PATH so finance_tools.py can shell out to it
      PATH = "${pkgs.duckdb}/bin:$PATH";
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
          printf 'ANTHROPIC_API_KEY=%s\n' "$(cat ${config.age.secrets.anthropic-api-key.path})"
          printf 'OPENROUTER_API_KEY=%s\n' "$(cat ${config.age.secrets.open-router-api-key.path})"
        } > /run/open-webui-secrets/env
        chmod 600 /run/open-webui-secrets/env
      ''}";
    };
  };

  services.caddy.virtualHosts."chat.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:8080
  '';
}
