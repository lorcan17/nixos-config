{ domain, config, pkgs, ... }: {
  services.open-webui = {
    enable = true;
    host   = "127.0.0.1";
    port   = 8080;
    environment = {
      OLLAMA_BASE_URL = "http://localhost:11434";
      # Disable auth — Tailscale is the perimeter
      WEBUI_AUTH = "False";
    };
    environmentFile = "/run/open-webui-secrets/env";
  };

  # Write a KEY=value env file at service start from the agenix-decrypted secret.
  # Runs as root (+) so it can read the 0440 secret and write to /run.
  systemd.services.open-webui.serviceConfig.ExecStartPre =
    let
      secretPath = config.age.secrets.anthropic-api-key.path;
    in
    "+${pkgs.writeShellScript "open-webui-write-env" ''
      install -d -m 750 -o open-webui -g open-webui /run/open-webui-secrets
      printf 'ANTHROPIC_API_KEY=%s\n' "$(cat ${secretPath})" \
        > /run/open-webui-secrets/env
      chmod 640 /run/open-webui-secrets/env
      chown open-webui:open-webui /run/open-webui-secrets/env
    ''}";

  services.caddy.virtualHosts."chat.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:8080
  '';
}
