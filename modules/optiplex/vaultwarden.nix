{ domain, ... }:
{
  # Vaultwarden — lightweight Bitwarden-compatible server.
  #
  # Clients (Mac, Android, browser) connect to https://vault.blue-apricots.com
  # All data is stored in /var/lib/vaultwarden.
  # Backups: should be added to backups.nix when implemented.

  services.vaultwarden = {
    enable = true;
    dbBackend = "sqlite"; # Lightweight and standard for homelab scale.
    config = {
      DOMAIN = "https://vault.${domain}";
      SIGNUPS_ALLOWED = false; # Set to true for first run to create your account, then false.
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
    };
  };

  services.caddy.virtualHosts."vault.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:8222
  '';
}
