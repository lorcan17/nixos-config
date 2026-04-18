{ config, pkgs, domain, ... }:
let
  ns = "wg-mullvad";
in {
  # Transmission-daemon running inside the wg-mullvad network namespace.
  #
  # Why NetworkNamespacePath and not a kill-switch rule?
  # The netns approach means Transmission literally cannot route packets outside
  # the tunnel — no iptables gymnastics, no race at startup. If wg-mullvad goes
  # down, the RPC port vanishes too. See DECISIONS.md (2026-04-16).
  #
  # RPC is bound to 127.0.0.1:9091 inside the netns only. To reach it from the
  # host (e.g. for Radarr or a future Caddy vhost) you'll need either:
  #   a) a veth pair bridging host → netns (more wiring in vpn.nix), or
  #   b) `sudo ip netns exec wg-mullvad transmission-remote ...` for ad-hoc use.
  #
  # Download dir defaults to /var/lib/transmission/Downloads — symlink or bind-
  # mount to a media disk once Radarr arrives.
  #
  # Smoke test:
  #   sudo ip netns exec wg-mullvad curl -s http://127.0.0.1:9091/transmission/rpc
  #   → 409 with X-Transmission-Session-Id header means the daemon is alive
  #   sudo ip netns exec wg-mullvad curl -s https://am.i.mullvad.net/json
  #   → mullvad_exit_ip: true confirms traffic exits via the tunnel

  services.transmission = {
    enable          = true;
    package         = pkgs.transmission_4;
    openRPCPort     = false; # behind netns; never expose directly to host
    settings = {
      rpc-bind-address          = "192.168.254.2"; # veth-tr-ns — reachable from host via veth
      rpc-port                  = 9091;
      rpc-whitelist-enabled     = false;  # whitelist is moot inside netns
      rpc-authentication-required = false;

      # Peer port — must be open inside the netns for seeding
      peer-port                 = 51413;
      peer-port-random-on-start = false;

      # Sane defaults; tune once you're running
      speed-limit-up-enabled    = false;
      speed-limit-down-enabled  = false;
      ratio-limit-enabled       = false;
      incomplete-dir-enabled    = true;   # stage partial downloads separately
    };
  };

  # Uptime Kuma heartbeat — pings every 60s; set monitor interval to 120s in Kuma UI.
  # Checks transmission is active before pinging so Kuma sees a real down signal.
  systemd.services.transmission-kuma-heartbeat = {
    description = "Uptime Kuma heartbeat for Transmission";
    serviceConfig = {
      Type    = "oneshot";
      ExecStart = pkgs.writeShellScript "transmission-kuma-heartbeat" ''
        if systemctl is-active --quiet transmission; then
          status=up msg=OK
        else
          status=down msg=transmission-not-running
        fi
        ${pkgs.curl}/bin/curl -fsS \
          "https://kuma.blue-apricots.com/api/push/u0T40rYigelnoCpF5cwPuKcqgcCbhH4N?status=$status&msg=$msg&ping="
      '';
    };
  };

  systemd.timers.transmission-kuma-heartbeat = {
    wantedBy  = [ "timers.target" ];
    timerConfig = {
      OnBootSec       = "60s";
      OnUnitActiveSec = "60s";
    };
  };

  services.caddy.virtualHosts."torrents.${domain}".extraConfig = ''
    import cloudflare_tls
    reverse_proxy 192.168.254.2:9091
  '';

  # Move the unit into the wg-mullvad netns
  systemd.services.transmission = {
    after    = [ "wg-mullvad.service" ];
    requires = [ "wg-mullvad.service" ];
    serviceConfig = {
      NetworkNamespacePath = "/var/run/netns/${ns}";
      OnFailure            = "ntfy-alert@%n.service";
    };
  };
}
