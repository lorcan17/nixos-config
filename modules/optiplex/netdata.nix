{ domain, ... }:
{
  # Netdata — high-resolution real-time monitoring.
  # Available at https://monitor.blue-apricots.com (renamed from netdata subdomain per project preference)
  #
  # Note: Previous deployment (2026-04-18) failed because the web UI couldn't find its files.
  # This version uses the standard services.netdata.package to ensure all paths are correctly linked.

  services.netdata = {
    enable = true;
    # Netdata binds to 127.0.0.1 by default on NixOS for security.
    config = {
      global = {
        "memory mode" = "ram";
        "history" = 3600; # 1 hour of high-res history
      };
      web = {
        "allow connections from" = "localhost";
      };
    };
  };

  services.caddy.virtualHosts."monitor.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:19999
  '';
}
