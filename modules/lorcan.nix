{ pkgs, lib, ... }:
let
  homeDir = if pkgs.stdenv.isDarwin then "/Users/lorcan" else "/home/lorcan";
in
lib.mkMerge [
  # Cross-platform base
  {
    # Enable zsh system-wide — required for it to be a valid login shell
    programs.zsh.enable = true;

    users.users.lorcan.home = homeDir;

    # home-manager entry point: who this config belongs to
    home-manager.users.lorcan = {
      home.username      = "lorcan";
      home.homeDirectory = homeDir;
      home.stateVersion  = "25.05";
    };
  }

  # Darwin-only: identifies which user per-user settings apply to
  # (dock, finder, keyboard, homebrew, screencapture, etc.)
  (lib.mkIf pkgs.stdenv.isDarwin {
    system.primaryUser = "lorcan";
  })

  # NixOS-only: full user account (macOS users exist outside Nix)
  (lib.mkIf pkgs.stdenv.isLinux {
    users.users.lorcan = {
      isNormalUser = true;
      extraGroups  = [ "wheel" "networkmanager" ];
      shell        = pkgs.zsh;
    };
  })
]
