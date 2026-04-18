{ config, pkgs, ... }:
{
  # Caddy reverse proxy.
  # {$DOMAIN} and {$CF_API_TOKEN} are substituted by Caddy at load time from the
  # EnvironmentFiles below — neither value lands in a committed .nix file.
  #
  # TLS: ACME DNS-01 via Cloudflare. No port-forwarding required; works entirely
  # over Tailscale. Certs are real Let's Encrypt — no browser or mobile warnings.
  #
  # First build: Nix will fail with the correct hash for the Cloudflare plugin.
  # Copy it into the `hash` field below, then rebuild.

  age.secrets.caddy-domain = {
    file  = ../../secrets/caddy-domain.age;
    mode  = "0400";
    owner = "caddy";
    group = "caddy";
  };

  age.secrets.caddy-cf-api-token = {
    file  = ../../secrets/caddy-cf-api-token.age;
    mode  = "0400";
    owner = "caddy";
    group = "caddy";
  };

  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.2" ];
      hash = "sha256-7DGnojZvcQBZ6LEjT0e5O9gZgsvEeHlQP9aKaJIs/Zg=";
    };
    virtualHosts."{$DOMAIN}".extraConfig = ''
      tls {
        dns cloudflare {$CF_API_TOKEN}
      }
      respond "hello from optiplex — caddy is working"
    '';
  };

  # Both secrets are env-file format; Caddy reads them at startup.
  systemd.services.caddy.serviceConfig.EnvironmentFile = [
    config.age.secrets.caddy-domain.path
    config.age.secrets.caddy-cf-api-token.path
  ];

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
