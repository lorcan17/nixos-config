{ lib, isDarwin, ... }:
{
  # Cross-platform: SSH *client* config via home-manager
  home-manager.users.lorcan = {
    programs.ssh = {
      enable              = true;
      enableDefaultConfig = false; # opt out of deprecated auto-defaults

      matchBlocks = {
        # Global defaults applied to all hosts
        "*" = {
          addKeysToAgent = "yes";
          identityFile   = "~/.ssh/id_ed25519";
        };

        optiplex = {
          hostname            = "optiplex"; # resolves via Tailscale MagicDNS
          user                = "lorcan";
          serverAliveInterval = 60;
        };
      };
    };
  };
}
# NixOS-only: sshd + firewall. networking.firewall doesn't exist on nix-darwin.
// lib.optionalAttrs (!isDarwin) {
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = true;  # TODO: switch to key-only once key is deployed
      PermitRootLogin        = "no";
    };
  };

  networking.firewall.allowedTCPPorts = [ 22 ];
}
