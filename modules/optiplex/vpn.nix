{ config, pkgs, ... }:
let
  ns = "wg-mullvad";
in {
  # Mullvad WireGuard tunnel inside a dedicated network namespace.
  #
  # Why netns and not wg-quick on the host?
  # The host network (Tailscale, SSH, Caddy) must keep using the normal route.
  # Putting wg0 in its own namespace means only processes explicitly launched
  # into `wg-mullvad` see the tunnel — kill-switch by construction, no iptables
  # gymnastics. See DECISIONS.md (2026-04-16: torrent isolation via netns).
  #
  # How a consumer joins the tunnel:
  #   systemd.services.<name>.serviceConfig.NetworkNamespacePath =
  #     "/var/run/netns/${ns}";
  #
  # Smoke test after rebuild:
  #   sudo ip netns exec wg-mullvad curl -s https://am.i.mullvad.net/json
  # → should report mullvad_exit_ip: true and a Swedish exit.

  age.secrets.mullvad-wg-config = {
    file  = ../../secrets/mullvad-wg-config.age;
    mode  = "0400";
    # owner defaults to root; the systemd unit below runs as root.
  };

  # Make `wg`, `wg-quick` available for interactive diagnostics inside the netns
  # (e.g. `sudo ip netns exec wg-mullvad wg show`). The unit itself uses its own
  # `path =` and doesn't depend on this.
  environment.systemPackages = [ pkgs.wireguard-tools ];

  systemd.services.wg-mullvad = {
    description = "Mullvad WireGuard tunnel inside ${ns} netns";
    wantedBy    = [ "multi-user.target" ];
    after       = [ "network-online.target" ];
    wants       = [ "network-online.target" ];

    path = with pkgs; [ iproute2 wireguard-tools ];

    serviceConfig = {
      Type            = "oneshot";
      RemainAfterExit = true;
    };

    script = ''
      set -euo pipefail
      conf=${config.age.secrets.mullvad-wg-config.path}

      # 1. namespace + loopback
      ip netns add ${ns}
      ip -n ${ns} link set lo up

      # 2. resolv.conf for the netns (mullvad DNS, no leaks to host resolver)
      mkdir -p /etc/netns/${ns}
      grep '^DNS' "$conf" \
        | sed 's/^DNS *= *//' \
        | tr ',' '\n' \
        | sed 's/^[[:space:]]*/nameserver /' \
        > /etc/netns/${ns}/resolv.conf

      # 3. create wg0 in the host ns, then move it into the netns
      ip link add wg0 type wireguard
      ip link set wg0 netns ${ns}

      # 4. apply wg config — strip wg-quick-only keys ourselves, since
      # `wg-quick strip` refuses any filename that doesn't end in `.conf`
      # (and the agenix-decrypted file lives at /run/agenix/mullvad-wg-config).
      ip netns exec ${ns} wg setconf wg0 <(
        sed -E '/^[[:space:]]*(Address|DNS|MTU|Table|PreUp|PostUp|PreDown|PostDown|SaveConfig|FwMark)[[:space:]]*=/d' "$conf"
      )

      # 5. address(es) on wg0 inside the netns (mullvad gives v4 + v6)
      for addr in $(grep '^Address' "$conf" | sed 's/^Address *= *//' | tr ',' ' '); do
        ip -n ${ns} addr add "$addr" dev wg0
      done

      # 6. up + default route through the tunnel
      ip -n ${ns} link set wg0 up
      ip -n ${ns} route add default dev wg0
    '';

    preStop = ''
      ${pkgs.iproute2}/bin/ip -n ${ns} link del wg0 || true
      ${pkgs.iproute2}/bin/ip netns del ${ns} || true
      rm -f /etc/netns/${ns}/resolv.conf
    '';
  };
}
