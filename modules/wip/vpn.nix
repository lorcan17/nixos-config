{ config, pkgs, ... }:
{
  # Mullvad WireGuard VPN — scoped to Transmission only via kill switch.
  # Everything else (Tailscale, SSH, Ollama) stays on the normal network.
  # Fill in the values from your downloaded Mullvad WireGuard config file.

  networking.wg-quick.interfaces.mullvad = {
    privateKeyFile = config.age.secrets.mullvad-privkey.path;

    address = [ "REPLACE_10.x.x.x/32" ]; # Address field from Mullvad config
    dns     = [ "10.64.0.1" ];           # Mullvad DNS — also blocks ads

    peers = [{
      publicKey  = "REPLACE_PUBLIC_KEY";      # PublicKey field from Mullvad config
      endpoint   = "REPLACE_IP:51820";        # Endpoint field from Mullvad config
      allowedIPs = [ "0.0.0.0/0" ];
      persistentKeepalive = 25;
    }];

    # Kill switch: Transmission's traffic is dropped if it tries to use eno1
    # instead of the VPN interface — prevents ISP from seeing torrent traffic.
    postUp = ''
      ${pkgs.iptables}/bin/iptables -A OUTPUT -m owner --gid-owner transmission -o eno1 -j DROP
      ${pkgs.iptables}/bin/iptables -A OUTPUT -m owner --gid-owner transmission -o mullvad -j ACCEPT
    '';
    postDown = ''
      ${pkgs.iptables}/bin/iptables -D OUTPUT -m owner --gid-owner transmission -o eno1 -j DROP
      ${pkgs.iptables}/bin/iptables -D OUTPUT -m owner --gid-owner transmission -o mullvad -j ACCEPT
    '';
  };
}
