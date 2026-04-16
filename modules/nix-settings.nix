{ pkgs, lib, ... }:
lib.mkMerge [
  # Cross-platform
  {
    # Needed for terraform (BSL 1.1) and any other non-open-source packages.
    nixpkgs.config.allowUnfree = true;
  }

  # Darwin: Determinate Systems manages the Nix daemon — nix-darwin should not conflict.
  # Flakes, experimental-features, binary caches, and GC are handled by Determinate's
  # own daemon. nix.settings and nix.gc are unavailable when this is false.
  (lib.mkIf pkgs.stdenv.isDarwin {
    nix.enable = false;
  })

  # NixOS: we manage Nix directly — enable flakes and the new nix command.
  (lib.mkIf pkgs.stdenv.isLinux {
    nix.settings.experimental-features = [ "nix-command" "flakes" ];
  })
]
