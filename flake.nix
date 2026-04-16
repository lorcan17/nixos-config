{
  description = "Lorcan's nix-darwin + NixOS config";

  inputs = {
    nixpkgs.url     = "github:NixOS/nixpkgs/nixos-unstable";
    nix-darwin      = { url = "github:LnL7/nix-darwin"; inputs.nixpkgs.follows = "nixpkgs"; };
    home-manager    = { url = "github:nix-community/home-manager"; inputs.nixpkgs.follows = "nixpkgs"; };
    agenix          = { url = "github:ryantm/agenix"; inputs.nixpkgs.follows = "nixpkgs"; };
  };

  outputs = { self, nixpkgs, nix-darwin, home-manager, agenix }:
    let
      # Auto-import every .nix file directly inside `dir` (non-recursive).
      # Used to route modules/{shared,mac,optiplex}/* into the right host.
      importDir = dir:
        let
          entries = builtins.readDir dir;
          nixFiles = builtins.filter
            (name: entries.${name} == "regular" && builtins.match ".*\\.nix" name != null)
            (builtins.attrNames entries);
        in map (name: dir + "/${name}") nixFiles;
    in {

    darwinConfigurations."lorcans-mac" = nix-darwin.lib.darwinSystem {
      system = "aarch64-darwin";
      specialArgs = { inherit agenix; isDarwin = true; };
      modules = [
        home-manager.darwinModules.home-manager
        agenix.darwinModules.default
        { home-manager.useGlobalPkgs = true; home-manager.useUserPackages = true; }
      ]
      ++ importDir ./modules/shared
      ++ importDir ./modules/mac;
    };

    nixosConfigurations.optiplex = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = { inherit agenix; isDarwin = false; };
      modules = [
        home-manager.nixosModules.home-manager
        agenix.nixosModules.default
        { home-manager.useGlobalPkgs = true; home-manager.useUserPackages = true; }
      ]
      ++ importDir ./modules/shared
      ++ importDir ./modules/optiplex;
    };

  };
}
