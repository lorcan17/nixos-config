{ lib, isDarwin, ... }:
{
  # Cross-platform: nixpkgs.config works on both NixOS and nix-darwin
  # Needed for terraform (BSL 1.1) and any other non-open-source packages.
  nixpkgs.config.allowUnfree = true;

  # Garbage collection and store optimization.
  # Keeps the disk from hitting 95% again.
  nix.gc = {
    automatic = true;
    # Run every Sunday at 3:15 AM
    dates = if isDarwin then "Sun 03:15" else "weekly";
    options = "--delete-older-than 7d";
  };

  # Automatically hardlink identical files in the store.
  nix.settings.auto-optimise-store = true;

  # NixOS: we manage Nix directly — enable flakes and the new nix command.
  nix.settings.experimental-features = lib.mkIf (!isDarwin) [ "nix-command" "flakes" ];
}
