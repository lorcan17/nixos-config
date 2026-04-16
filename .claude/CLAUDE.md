# nix-config — NixOS + nix-darwin

## Architecture
This repo manages two machines:
- `lorcans-mac` — aarch64-darwin (Apple Silicon MacBook)
- `optiplex` — x86_64-linux (Dell OptiPlex homelab server)

## Module layout
Modules live in four subdirectories of `modules/`, each with a clear routing rule:

```
modules/
  shared/     → imported into BOTH hosts (shell, git, ssh, secrets, terminal-tools, etc.)
  mac/        → imported into Mac only (mac-homebrew, mac-system, etc.)
  optiplex/   → imported into OptiPlex only (tailscale, ollama, hardware-optiplex, etc.)
  wip/        → NOT imported anywhere — staging area for in-progress modules
```

`flake.nix` uses a small `importDir` helper (`builtins.readDir` + filter) to auto-load each directory into the right host. **You never edit `flake.nix` to add a feature.**

## Key pattern rules
- One file per feature (e.g., `ssh.nix` handles NixOS server + home-manager client config).
- Adding a feature = create one `.nix` file in the right subdirectory. Nothing else changes.
- Promoting a WIP module to live = `git mv modules/wip/foo.nix modules/optiplex/foo.nix` (or `mac/`, or `shared/`).
- Shared modules that need platform branching: use `lib.optionalAttrs` (not `lib.mkIf`) for platform-exclusive *option paths* so eval succeeds on both systems.
- Paths inside modules: remember that `modules/shared/secrets.nix` is two levels deep — use `../../secrets/...` for files at repo root.

## Secrets
- Managed by agenix — encrypted `.age` files in `secrets/`.
- Decrypted at activation: Mac uses `~/.ssh/id_ed25519`, OptiPlex uses `/etc/ssh/ssh_host_ed25519_key`.
- Never put plaintext secrets in `.nix` files.
- `secrets/secrets.nix` declares which public keys can decrypt each secret.
- Creating an encrypted secret: `cd secrets && agenix -e <name>.age`.

## Testing changes
```bash
# Mac — build without switching (dry run)
darwin-rebuild build --flake .#lorcans-mac

# Mac — switch
darwin-rebuild switch --flake .#lorcans-mac

# OptiPlex — test without persisting across reboot
ssh optiplex "cd ~/nix-config && git pull && sudo nixos-rebuild test --flake .#optiplex"

# OptiPlex — switch (persist)
ssh optiplex "cd ~/nix-config && git pull && sudo nixos-rebuild switch --flake .#optiplex"
```

## Common tasks
- **Add a new service to OptiPlex:** create `modules/optiplex/service-name.nix`.
- **Add a Mac-only setting:** create `modules/mac/thing.nix`.
- **Add something cross-platform:** create `modules/shared/thing.nix`.
- **Stash a half-built module:** drop it in `modules/wip/` — it won't be imported.
- **Add a secret:** add entry to `secrets/secrets.nix`, run `agenix -e secret-name.age`, declare it in `modules/shared/secrets.nix`, reference it as `config.age.secrets.secret-name.path`.
- **Add a homebrew cask:** edit `modules/mac/mac-homebrew.nix` under `homebrew.casks`.
- **Add a CLI tool:** edit `modules/shared/terminal-tools.nix` or `modules/shared/shell.nix`.

## Style
- Use `lib.mkDefault` for values that individual machines might override.
- Group related options together with comments.
- Keep module filenames descriptive — `tailscale.nix`, not `ts.nix`.
