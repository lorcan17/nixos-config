# nix-config — Dendritic NixOS + nix-darwin

## Architecture
This repo manages two machines using the Dendritic Nix pattern:
- `lorcans-mac` — aarch64-darwin (Apple Silicon MacBook)
- `optiplex` — x86_64-linux (Dell OptiPlex homelab server)

## Key pattern rules
- Every .nix file in `modules/` is a flake-parts module — auto-imported via import-tree
- One file per feature (e.g., `ssh.nix` handles NixOS server + home-manager client config)
- Cross-platform config uses `flake.modules.nixos.*`, `flake.modules.darwin.*`, `flake.modules.homeManager.*`
- Never manually import modules in flake.nix — import-tree handles it
- Adding a feature = creating one .nix file in modules/. Nothing else changes.

## Secrets
- Managed by agenix — encrypted .age files in `secrets/`
- Decrypted at activation using host SSH key
- Never put plaintext secrets in .nix files
- `secrets/secrets.nix` declares which public keys can decrypt each secret

## Testing changes
```bash
# Mac — build without switching (dry run)
darwin-rebuild build --flake .#lorcans-mac

# Mac — switch
darwin-rebuild switch --flake .#lorcans-mac

# OptiPlex — test without persisting
ssh optiplex "cd ~/nix-config && git pull && sudo nixos-rebuild test --flake .#optiplex"

# OptiPlex — switch (persist)
ssh optiplex "cd ~/nix-config && git pull && sudo nixos-rebuild switch --flake .#optiplex"
```

## Common tasks
- Add a new service: create `modules/service-name.nix` with appropriate flake.modules declarations
- Add a secret: add entry to `secrets/secrets.nix`, run `agenix -e secret-name.age`, reference in module as `config.age.secrets.secret-name.path`
- Add a homebrew cask: add to `modules/mac-homebrew.nix` under `homebrew.casks`
- Add a CLI tool: add to `modules/terminal-tools.nix` or `modules/shell.nix` home.packages

## Style
- Use `lib.mkDefault` for values that individual machines might override
- Group related options together with comments
- Use descriptive module names in `flake.modules.*` (e.g., `flake.modules.nixos.ssh` not `flake.modules.nixos.a`)
