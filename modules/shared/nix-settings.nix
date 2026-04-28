{ lib, isDarwin, ... }:
{
  # Cross-platform: nixpkgs.config works on both NixOS and nix-darwin
  # Needed for terraform (BSL 1.1) and any other non-open-source packages.
  nixpkgs.config.allowUnfree = true;
}
// lib.optionalAttrs isDarwin {
  # Mac runs Determinate Nix, which manages the Nix installation itself.
  # nix-darwin must stand down — disabling this also makes any `nix.*` option
  # paths (gc, settings, etc.) unavailable on darwin, so we don't set them here.
  # GC on Mac is Determinate's responsibility.
  nix.enable = false;
}
// lib.optionalAttrs (!isDarwin) {
  # NixOS: we manage Nix directly.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 7d";
  };
  nix.settings.auto-optimise-store = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
