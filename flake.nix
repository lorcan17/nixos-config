{
  description = "Lorcan's nix-darwin + NixOS config";

  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    nix-darwin      = { url = "github:LnL7/nix-darwin"; inputs.nixpkgs.follows = "nixpkgs"; };
    home-manager    = { url = "github:nix-community/home-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
    # agenix — enable when adding the OptiPlex
    # agenix = { url = "github:ryantm/agenix"; inputs.nixpkgs.follows = "nixpkgs"; };
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager }: {

    darwinConfigurations."lorcans-mac" = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      specialArgs = { isDarwin = true; };
      modules = [
        home-manager.darwinModules.home-manager
        { home-manager.useGlobalPkgs = true; home-manager.useUserPackages = true; }

        # Core
        ./modules/nix-settings.nix
        ./modules/lorcan.nix

        # Shell and tools
        ./modules/git.nix
        ./modules/shell.nix
        ./modules/ssh.nix
        ./modules/terminal-tools.nix
        ./modules/vim.nix

        # Mac system config
        ./modules/mac-system.nix
        ./modules/mac-keyboard.nix
        ./modules/mac-homebrew.nix
        ./modules/mac-fonts.nix
        ./modules/mac-dev.nix
      ];
    };

    # OptiPlex — homelab server
    # Minimal module set to get the base system onto the flake.
    # Additional modules (tailscale, docker, monitoring, secrets, etc.) to be
    # layered in one at a time via nixos-rebuild test once this base works.
    nixosConfigurations.optiplex = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { isDarwin = false; };
      modules = [
        home-manager.nixosModules.home-manager
        { home-manager.useGlobalPkgs = true; home-manager.useUserPackages = true; }

        # Core (cross-platform)
        ./modules/nix-settings.nix
        ./modules/lorcan.nix

        # Shell and tools (home-manager; cross-platform)
        ./modules/git.nix
        ./modules/shell.nix
        ./modules/ssh.nix
        ./modules/terminal-tools.nix
        ./modules/vim.nix

        # OptiPlex-specific
        ./modules/hardware-optiplex.nix
        ./modules/networking-optiplex.nix

        # Layer in after base boot is working:
        # ./modules/tailscale.nix
        # ./modules/ollama.nix
        # ./modules/openclaw.nix
        # ./modules/open-webui.nix
        # ./modules/docker.nix
        # ./modules/vpn.nix
        # ./modules/torrenting.nix
        # ./modules/secrets.nix
        # ./modules/security.nix
        # ./modules/monitoring.nix
        # ./modules/backups.nix
        # ./modules/obsidian.nix
      ];
    };

  };
}
