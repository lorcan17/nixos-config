{ config, ... }:
{
  services.transmission = {
    enable = true;
    group  = "transmission"; # matches the kill switch in vpn.nix

    settings = {
      download-dir           = "/data/downloads/complete";
      incomplete-dir         = "/data/downloads/incomplete";
      incomplete-dir-enabled = true;

      # Bind to VPN interface — Transmission can't connect if VPN is down
      bind-address-ipv4 = "REPLACE_10.x.x.x"; # same address as vpn.nix

      rpc-enabled               = true;
      rpc-port                  = 9091;
      rpc-whitelist-enabled     = true;
      rpc-whitelist             = "127.0.0.1,192.168.1.*,100.64.*.*"; # LAN + Tailscale
      rpc-authentication-required = true;
      rpc-username              = "lorcan";

      peer-port               = 51413;
      peer-port-random-on-start = false;
      encryption              = 2; # require encrypted peers
      dht-enabled             = true;
      pex-enabled             = true;

      speed-limit-up         = 500; # KB/s
      speed-limit-up-enabled = true;
      ratio-limit            = 2.0;
      ratio-limit-enabled    = true;
    };

    credentialsFile = config.age.secrets.transmission.path;
  };

  networking.firewall.allowedTCPPorts = [ 51413 ];
  networking.firewall.allowedUDPPorts = [ 51413 ];

  systemd.tmpfiles.rules = [
    "d /data/downloads/complete   0775 transmission transmission"
    "d /data/downloads/incomplete 0775 transmission transmission"
  ];
}
