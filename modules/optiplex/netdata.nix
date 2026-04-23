{ domain, ... }:
{
  # Netdata — high-resolution real-time monitoring.
  # Available at https://netdata.blue-apricots.com

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

  services.caddy.virtualHosts."netdata.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy localhost:19999
  '';
}
