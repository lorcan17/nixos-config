# agenix public key declarations.
# Each secret maps to the public keys that can decrypt it.
# Add a key here, then run: cd secrets && agenix -e <secret-name>.age
#
# To get your public keys:
#   Mac:      cat ~/.ssh/id_ed25519.pub
#   OptiPlex: ssh optiplex 'cat /etc/ssh/ssh_host_ed25519_key.pub'

let
  # REPLACE: paste your actual public keys
  lorcan   = "ssh-ed25519 AAAAC3Nza... lorcan@macbook";
  optiplex = "ssh-ed25519 AAAAC3Nza... root@optiplex";
in {
  "tailscale-auth.age".publicKeys    = [ lorcan optiplex ];
  "transmission.age".publicKeys      = [ lorcan optiplex ];
  "mullvad-privkey.age".publicKeys   = [ lorcan optiplex ];
}
