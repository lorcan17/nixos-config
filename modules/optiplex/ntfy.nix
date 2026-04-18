{ config, pkgs, ... }:
{
  services.ntfy-sh = {
    enable = true;
    settings = {
      # base-url is required by the NixOS module but can't use {$DOMAIN} syntax.
      # The real value is injected at runtime via NTFY_BASE_URL from the domain secret.
      base-url            = "https://placeholder.invalid";
      listen-http         = ":2586";
      behind-proxy        = true;
      auth-default-access = "allow-all";
    };
  };

  # Read domain secret at service start and export NTFY_BASE_URL to override the placeholder.
  systemd.services.ntfy-sh.serviceConfig = {
    ExecStartPre = pkgs.writeShellScript "ntfy-set-base-url" ''
      domain=$(cat ${config.age.secrets.domain.path})
      echo "NTFY_BASE_URL=https://ntfy.$domain" > /run/ntfy-base-url
      chmod 400 /run/ntfy-base-url
    '';
    EnvironmentFile = "/run/ntfy-base-url";
  };

  # Caddy vhost — proxies ntfy.{$DOMAIN} → localhost:2586
  services.caddy.virtualHosts."ntfy.{$DOMAIN}".extraConfig = ''
    tls {
      dns cloudflare {$CF_API_TOKEN}
    }
    reverse_proxy localhost:2586
  '';
}
