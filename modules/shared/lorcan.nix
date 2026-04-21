{ pkgs, lib, isDarwin, ... }:
let
  homeDir = if isDarwin then "/Users/lorcan" else "/home/lorcan";
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
# Darwin-only option path — must be structurally absent on NixOS.
// lib.optionalAttrs isDarwin {
  system.primaryUser = "lorcan";
}
// lib.optionalAttrs (!isDarwin) {
  security.sudo.wheelNeedsPassword = false;
}
