{ pkgs, agenix, ... }:
{
  home-manager.users.lorcan = {
    home.packages = with pkgs; [
      # Better Unix defaults
      ripgrep  # rg — fast grep that respects .gitignore
      fd       # find replacement
      bat      # cat with syntax highlighting
      eza      # ls replacement with git integration
      jq       # JSON processor
      tldr     # practical man pages

      # System monitoring
      btop     # pretty htop with graphs

      # Network
      wget
      curl

      # Misc
      unzip
      nodejs_24
      agenix.packages.${pkgs.system}.default
      tmux
    ];
  };
}
