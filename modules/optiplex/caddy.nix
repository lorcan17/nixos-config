{ config, ... }:
{
  # Caddy reverse proxy.
  # Domain is read from an agenix secret in env-file format (`DOMAIN=...`) and
  # substituted into the Caddyfile via {$DOMAIN} at Caddy load time — so the
  # real domain never lands in a committed .nix file.
  #
  # First-pass TLS: `tls internal` (Caddy's built-in self-signed CA). Browsers
  # will warn; click through. Swap to Let's Encrypt via DNS-01 once a DNS
  # provider API token is wired as a second agenix secret.

  # NOTE: this secret currently exists solely to feed Caddy's site-block header.
  # If another service ever needs the domain, rename to something less generic
  # (e.g. `caddy-domain`) and introduce a separate secret for the new consumer —
  # don't share this one, since ownership/mode are tuned for the caddy daemon.
  age.secrets.domain-name = {
    file  = ../../secrets/domain-name.age;
    mode  = "0400";
    owner = "caddy";
    group = "caddy";
  };

  services.caddy = {
    enable = true;
    virtualHosts."{$DOMAIN}".extraConfig = ''
      tls internal
      respond "hello from optiplex — caddy is working"
    '';
  };

  systemd.services.caddy.serviceConfig.EnvironmentFile =
    config.age.secrets.domain-name.path;

  networking.firewall.allowedTCPPorts = [ 80 443 ];
}
