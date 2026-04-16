{ pkgs, lib, ... }:
let
  isDarwin = pkgs.stdenv.isDarwin;
  homeDir  = if isDarwin then "/Users/lorcan" else "/home/lorcan";
in
{
  # Enable zsh system-wide — required for it to be a valid login shell
  programs.zsh.enable = true;

  # User account — base shared by both platforms, with NixOS-only fields merged in
  users.users.lorcan = {
    home = homeDir;
  } // lib.optionalAttrs (!isDarwin) {
    isNormalUser = true;
    extraGroups  = [ "wheel" "networkmanager" ];
    shell        = pkgs.zsh;
  };

  # home-manager entry point: who this config belongs to
  home-manager.users.lorcan = {
    home.username      = "lorcan";
    home.homeDirectory = homeDir;
    home.stateVersion  = "25.05";
  };
}
# Darwin-only: the option path system.primaryUser doesn't exist on NixOS,
# so it must be structurally absent (not just mkIf false) to avoid eval errors.
// lib.optionalAttrs isDarwin {
  system.primaryUser = "lorcan";
}
