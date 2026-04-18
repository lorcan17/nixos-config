{ ... }:
{
  home-manager.users.lorcan.programs.zsh.shellAliases = {
    rebuild      = "cd ~/nix-config && git pull && sudo nixos-rebuild switch --flake .#optiplex";
    rebuild-hard = "cd ~/nix-config && git fetch origin && git reset --hard origin/main && sudo nixos-rebuild switch --flake .#optiplex";
  };
}
