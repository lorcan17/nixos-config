{ lib, isDarwin, ... }:
{
  # Cross-platform: nixpkgs.config works on both NixOS and nix-darwin
  # Needed for terraform (BSL 1.1) and any other non-open-source packages.
  nixpkgs.config.allowUnfree = true;
}
# Darwin: Determinate Systems manages the Nix daemon; nix-darwin should not conflict.
// lib.optionalAttrs isDarwin {
  nix.enable = false;
}
# NixOS: we manage Nix directly — enable flakes and the new nix command.
// lib.optionalAttrs (!isDarwin) {
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
}
