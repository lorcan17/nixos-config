{ pkgs, ... }:
{
  home-manager.users.lorcan = {
    fonts.fontconfig.enable = true;

    home.packages = [
      pkgs.nerd-fonts.jetbrains-mono  # primary coding font — clear and readable
      pkgs.nerd-fonts.fira-code       # alternative with ligatures
    ];
  };
}
