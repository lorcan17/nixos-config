{ isDarwin, ... }:
{
  # agenix secret declarations for the OptiPlex and Mac.
  # On Mac, we use the user's SSH key for decryption.
  age.identityPaths = if isDarwin 
    then [ "/Users/lorcan/.ssh/id_ed25519" ]
    else [ "/etc/ssh/ssh_host_ed25519_key" ];

  age.secrets = {
    fmp-api-key = {
      file  = ../../secrets/fmp-api-key.age;
      mode  = "0400";
      owner = "lorcan";
    };
    questrade-consumer-key = {
      file  = ../../secrets/questrade-consumer-key.age;
      mode  = "0400";
      owner = "lorcan";
    };
    anthropic-api-key = {
      file  = ../../secrets/anthropic-api-key.age;
      mode  = "0400";
      owner = "lorcan";
    };
    tailscale-authkey = {
      file = ../../secrets/tailscale-authkey.age;
      mode = "0400";
      # owner defaults to root; tailscaled reads this at daemon start
    };
    # caddy-domain is declared in modules/optiplex/caddy.nix — caddy-owned, not cross-platform.
    # domain is declared in modules/optiplex/finance.nix — bare domain for service URL construction.
  };
}
