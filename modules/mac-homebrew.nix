{ ... }:
{
  # nix-darwin manages Homebrew itself — don't install brew separately
  homebrew = {
    enable = true;
    onActivation = {
      autoUpdate = true;
      cleanup    = "zap"; # remove any cask not listed here on darwin-rebuild switch
    };

    casks = [
      # Browser
      "firefox"

      # Terminal
      "iterm2"

      # Notes / PKM
      "obsidian"

      # Networking
      "tailscale"

      # Dev tools
      "visual-studio-code"
      "dbeaver-community"  # Snowflake query client

      # Communication
      "slack"
      "zoom"
    ];
  };
}
