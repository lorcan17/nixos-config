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
    tailscale-authkey = {
      file = ../../secrets/tailscale-authkey.age;
      mode = "0400";
      # owner defaults to root; tailscaled reads this at daemon start
    };
    # domain-name is declared in modules/optiplex/caddy.nix — only needed there,
    # and must be owned by the `caddy` user (which doesn't exist on Mac).
  };
}
