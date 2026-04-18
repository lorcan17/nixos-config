{ config, pkgs, domain, ... }:
{
  # Caddy reverse proxy.
  # domain is a Nix string from modules/optiplex/config.nix (no longer a secret).
  # {$CF_API_TOKEN} is still substituted at runtime from the EnvironmentFile below.
  #
  # TLS: ACME DNS-01 via Cloudflare. No port-forwarding required; works entirely
  # over Tailscale. Certs are real Let's Encrypt — no browser or mobile warnings.
  #
  # First build: Nix will fail with the correct hash for the Cloudflare plugin.
  # Copy it into the `hash` field below, then rebuild.

  age.secrets.caddy-cf-api-token = {
    file  = ../../secrets/caddy-cf-api-token.age;
    mode  = "0400";
    owner = "caddy";
    group = "caddy";
  };

  services.caddy = {
    enable = true;
    package = pkgs.caddy.withPlugins {
      plugins = [ "github.com/caddy-dns/cloudflare@v0.2.4" ];
      hash = "sha256-Olz4W84Kiyldy+JtbIicVCL7dAYl4zq+2rxEOUTObxA=";
    };
    # Snippet defined once here; every service vhost uses `import cloudflare_tls`.
    # Changing TLS strategy = edit this block only.
    extraConfig = ''
      (cloudflare_tls) {
        tls {
          dns cloudflare {$CF_API_TOKEN}
        }
      }
    '';
    virtualHosts."${domain}".extraConfig = ''
      import cloudflare_tls
      respond "hello from optiplex — caddy is working"
    '';
  };

  systemd.services.caddy.serviceConfig.EnvironmentFile = [
    config.age.secrets.caddy-cf-api-token.path
  ];

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
