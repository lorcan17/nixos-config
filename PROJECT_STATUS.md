# nix-config — Project Status

> Living doc. Update when modules land or plans change. Last updated: 2026-04-16.

---

## Architecture

Two machines managed via flake-parts + Dendritic pattern (one file per feature, import-tree auto-loads).

```
lorcans-mac (aarch64-darwin)     optiplex (x86_64-linux)
─────────────────────────────    ──────────────────────────────
nix-darwin + home-manager        NixOS + home-manager
Shell: zsh, starship, direnv     Same shell config (shared modules)
Tools: ripgrep, bat, eza, fzf    Same tools (shared modules)
Homebrew: GUI apps, casks        —
Secrets: agenix (user SSH key)   Secrets: agenix (host SSH key)
                                 Ollama (CPU inference, :11434)
```

Secrets managed by agenix. Encrypted `.age` files in `secrets/`. Mac decrypts with `~/.ssh/id_ed25519`, OptiPlex with `/etc/ssh/ssh_host_ed25519_key`.

---

## Active Secrets

| Secret | Hosts | Purpose |
|---|---|---|
| `fmp-api-key` | Mac + OptiPlex | Financial Modelling Prep API, exported as `$FMP_API_KEY` in zsh |

---

## Services — OptiPlex

| Service | Module | Status | Notes |
|---|---|---|---|
| Ollama | `ollama.nix` | ✅ Running | CPU-only, `0.0.0.0:11434` |
| Tailscale | `tailscale.nix` | ⬜ Not started | Needed before public-facing services |
| Open-WebUI | `open-webui.nix` | ⬜ Not started | Depends on Ollama + reverse proxy |
| Docker | `docker.nix` | ⬜ Not started | Needed for some services |
| Reverse proxy | — | ⬜ Not started | Caddy or nginx; depends on domain + Tailscale |
| VPN/Mullvad | `vpn.nix` | ⬜ Not started | — |
| Torrenting | `torrenting.nix` | ⬜ Not started | Depends on VPN |
| Monitoring | `monitoring.nix` | ⬜ Not started | — |
| Backups | `backups.nix` | ⬜ Not started | — |
| Syncthing | `syncthing.nix` | ⬜ Not started | — |
| Security hardening | `security.nix` | ⬜ Not started | — |

---

## In Flight

_Nothing currently in progress._

---

## Backlog

### High priority
- [ ] **Tailscale** — VPN mesh between Mac and OptiPlex. Prerequisite for safe public access to services. Module stub exists at `modules/tailscale.nix`.
- [ ] **Domain name secret** — Add domain/subdomain as an agenix secret so it can be referenced in service configs without hardcoding.

### Medium priority
- [ ] **Reverse proxy (Caddy)** — Route subdomains to local services (e.g. `ollama.home.yourdomain.com`). Depends on: Tailscale + domain secret.
- [ ] **Open-WebUI** — Web frontend for Ollama. Depends on: reverse proxy.
- [ ] **Docker** — Required for some services. Evaluate whether NixOS-native alternatives cover the use cases first.
- [ ] **Monitoring** — Prometheus + Grafana, or Netdata. Low-effort win for homelab visibility.

### Low priority / someday
- [ ] **Syncthing** — File sync between Mac and OptiPlex.
- [ ] **Backups** — Restic or borgbackup for OptiPlex data.
- [ ] **VPN + Torrenting** — Mullvad with kill-switch, transmission behind it.
- [ ] **Security hardening** — fail2ban, SSH hardening, audit rules.
- [ ] **openclaw** — TBD what this is.

---

## Known Issues

| Issue | Affected | Notes |
|---|---|---|
| Ollama not yet verified | OptiPlex | `services.ollama.host`/`port` options added but not tested post-switch |
| Mac agenix not verified | Mac | First activation with `isDarwin` identity path not yet tested |

---

## Decision Log

| Date | Decision | Reason |
|---|---|---|
| 2026-04-16 | agenix for both Mac + OptiPlex | Consistent secret management; Mac uses user SSH key, OptiPlex uses host key |
| 2026-04-16 | Shared modules for shell/tools | Reduces drift; platform-exclusive options guarded with `lib.optionalAttrs` |
