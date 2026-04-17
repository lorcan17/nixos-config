# agenix public key declarations.
# Each secret maps to the public keys that can decrypt it.
# Add a key here, then run: cd secrets && agenix -e <secret-name>.age
#
# To get your public keys:
#   Mac:      cat ~/.ssh/id_ed25519.pub
#   OptiPlex: ssh optiplex 'cat /etc/ssh/ssh_host_ed25519_key.pub'

let
  # Public keys for encryption
  lorcan   = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAILNGNQUutGyQUKHEXNlchZggmMjnSkVnl0f8Hl1K8nb7 ltravers92@gmail.com";
  optiplex = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOcv94KIQ5JhrNxXmLcDByuCAmxu2h59sGYpzk87RQzy root@optiplex";
in {
  "fmp-api-key.age".publicKeys             = [ lorcan optiplex ];
  "tailscale-authkey.age".publicKeys       = [ lorcan optiplex ];
  "caddy-domain.age".publicKeys            = [ lorcan optiplex ];
  "domain.age".publicKeys                  = [ lorcan optiplex ];
  "mullvad-wg-config.age".publicKeys       = [ lorcan optiplex ];
  "questrade-consumer-key.age".publicKeys  = [ lorcan optiplex ];
  "anthropic-api-key.age".publicKeys       = [ lorcan optiplex ];
}
