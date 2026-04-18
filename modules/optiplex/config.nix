{ ... }:
{
  # Homelab domain — used directly in Nix string interpolation throughout optiplex modules.
  # Fill this in with your actual domain before rebuilding.
  # Eliminates the caddy-domain and domain agenix secrets.
  _module.args.domain = "blue-apricots.com";
}
