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
      ncdu     # ncurses-based disk usage analyzer
      dust     # visual disk usage

      # Network
      wget
      curl

      # Git / GitHub
      gh       # GitHub CLI

      # Misc
      unzip
      nodejs_24
      agenix.packages.${pkgs.system}.default
      tmux
    ];
  };
}
