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

**LLM strategy:** hybrid local/cloud. Local Ollama (Nous Hermes 8B on CPU) for cheap, high-frequency, low-stakes loops. Anthropic API for multi-step agentic work and heavy reasoning. Selected per-task via a config flag; API key held as an agenix secret.

---

## Active Secrets

| Secret | Hosts | Purpose |
|---|---|---|
| `fmp-api-key` | Mac + OptiPlex | Financial Modelling Prep API, exported as `$FMP_API_KEY` in zsh |
| `tailscale-authkey` | OptiPlex | Reusable auth key consumed by `tailscaled` at daemon start |
| `domain-name` | OptiPlex | **Caddy-only** (env-file format, `DOMAIN=...`). Rename if another service ever needs the domain — don't share. |
| `mullvad-wg-config` | OptiPlex | Single WireGuard `.conf` (Sweden exit) consumed by `vpn.nix` inside the `wg-mullvad` netns. |

**Planned:**
- `anthropic-api-key` — hybrid LLM offload for heavy reasoning
- `openai-api-key` — premium TTS for audiobooks (per-book opt-in)

---

## Services — OptiPlex

| Service | Module | Status | Notes |
|---|---|---|---|
| Ollama | `ollama.nix` | ✅ Running | CPU-only, `0.0.0.0:11434` |
| Tailscale | `tailscale.nix` | ✅ Running | Auth key via agenix; unblocks most other services |
| Mullvad + WireGuard | `vpn.nix` | 🟡 Built, untested | `wg-mullvad` netns; consumers join via `NetworkNamespacePath` |
| Torrenting | `torrenting.nix` | ⬜ Not started | Transmission inside `wg-mullvad` netns |
| Docker | `docker.nix` | ⬜ Not started | Accepted as required (Ghostfolio, LangAlpha, Immich are Docker-only) |
| Caddy reverse proxy | `caddy.nix` | ⬜ Not started | Depends on Tailscale + domain secret |
| Open-WebUI | `open-webui.nix` | ⬜ Not started | Depends on Ollama + reverse proxy |
| Kokoro TTS | `kokoro.nix` | ⬜ Not started | Shared engine for audiobook/article pipelines |
| Whisper.cpp | `whisper.nix` | ⬜ Not started | STT for meeting transcription |
| Ghostfolio | `ghostfolio.nix` | ⬜ Not started | Docker Compose; wires FMP key for market data |
| Monitoring | `monitoring.nix` | ⬜ Not started | Low-effort visibility win |
| Backups | `backups.nix` | ⬜ Not started | Restic or borgbackup |
| Syncthing | `syncthing.nix` | ⬜ Not started | Mac ↔ OptiPlex file sync |
| Security hardening | `security.nix` | ⬜ Not started | fail2ban, SSH, audit rules |

---

## In Flight

_Nothing currently in progress._

---

## Backlog

### Tier 1 — Foundations (unblock everything else)
- [x] **Tailscale** — VPN mesh; prerequisite for anything reachable off-LAN. _(landed 2026-04-16)_
- [x] **Domain name secret** — agenix entry so service configs don't hardcode. _(landed 2026-04-16)_
- [x] **Mullvad + WireGuard (vpn.nix)** — WireGuard config from agenix; introduces the `wg-mullvad` netns that `torrenting.nix` will reuse. _(landed 2026-04-16, smoke test pending)_
- [ ] **Docker (docker.nix)** — accepted as necessary. Ghostfolio, LangAlpha, and likely Immich are Docker-only upstream.
- [ ] **Caddy reverse proxy** — subdomain routing once Tailscale + domain are in.

### Tier 2 — First verticals (share TTS + job-runner scaffolding)
- [ ] **Gutenberg → audiobook pipeline** — fetch from gutenberg.org → chunk → Kokoro TTS → output `.m4b`. Zero legal/API risk; proves the TTS + job-runner scaffolding end-to-end.
- [ ] **Article → audio briefing** — RSS/URL → Readability extraction → Kokoro → single daily podcast file. Reuses the pipeline above.
- [ ] **Meeting transcription + summary** — Mac captures audio (BlackHole + capture script) → Syncthing to OptiPlex → whisper.cpp transcribes → Claude API summarises → markdown into Obsidian vault. All meetings are two-party (me + business partner) with consent.
- [ ] **Torrenting (torrenting.nix)** — Transmission in `wg-mullvad` netns. Enables public-domain audiobook downloads safely.

### Tier 3 — Finance stack
- [ ] **Ghostfolio** — Docker Compose; wire `$FMP_API_KEY` for market data. Accept the coupled Postgres + Redis as part of the island — don't share with NixOS-native services.
- [ ] **LLM portfolio updater** — Python job: broker CSV/PDF from a Syncthing folder → Claude API extracts activities → POST to Ghostfolio `/api/v1/order`.
- [ ] **Daily investment digest** — cron + Claude API: pull positions from Ghostfolio → prose summary → email or push to Obsidian.
- [ ] **LangAlpha** — multi-agent equity research stack (LangGraph + MongoDB + Playwright + paid APIs, ~$30–80/mo realistic). Defer until finance basics are stable and Docker/Tailscale are bedded in.

### Tier 4 — PKM + household
- [ ] **Paperless-ngx** — first-class `services.paperless` NixOS module. OCR paper docs into the PARA workflow.
- [ ] **Actual Budget** — self-hosted YNAB alternative; trivial Node systemd service.
- [ ] **Immich** — self-hosted photos. Docker; community Nix module lags upstream.
- [ ] **Open-WebUI** — browser frontend for Ollama.
- [ ] **Monitoring** — Prometheus + Grafana, or Netdata.

### Tier 5 — Experiments / someday
- [ ] **Car-hunt agent (Craigslist only)** — RSS per saved search → Claude API ranks against a spec (year, mileage, price band, Thule-box compatibility) → daily shortlist. Facebook Marketplace deliberately out of scope (anti-scraping too hostile); revisit via a Mac browser extension if needed.
- [ ] **Home Assistant** — if smart devices appear.
- [ ] **Backups (backups.nix)** — Restic or borgbackup for OptiPlex data.
- [ ] **Syncthing** — Mac ↔ OptiPlex; also underpins meeting + portfolio-updater pipelines.
- [ ] **Security hardening** — fail2ban, SSH hardening, audit rules.
- [ ] **openclaw** — TBD what this is.

---

## Known Issues

| Issue | Affected | Notes |
|---|---|---|
| Ollama not yet verified | OptiPlex | `services.ollama.host`/`port` options added but not tested post-switch |
| Mac agenix not verified | Mac | First activation with `isDarwin` identity path not yet tested |
| Mullvad netns not yet verified | OptiPlex | After switch, run `sudo ip netns exec wg-mullvad curl -s https://am.i.mullvad.net/json` — expect `mullvad_exit_ip: true` |

---

## Decision Log

Full ADR-lite entries with reasoning live in [DECISIONS.md](./DECISIONS.md). This is the index:

| Date | Decision |
|---|---|
| 2026-04-16 | Per-service Caddy vhost blocks (not a shared wildcard matcher) |
| 2026-04-16 | agenix on both Mac and OptiPlex |
| 2026-04-16 | Module subdirectories with auto-import (shared / mac / optiplex / wip) |
| 2026-04-16 | Keep Mullvad separate from Tailscale exit nodes |
| 2026-04-16 | Docker accepted as required |
| 2026-04-16 | Hybrid LLM: local Hermes 8B + Anthropic API |
| 2026-04-16 | Torrent isolation via NixOS network namespaces, not kill-switch |
| 2026-04-16 | TTS default = Kokoro (local); OpenAI TTS as per-book premium opt-in |
| 2026-04-16 | STT = whisper.cpp local (large-v3) |
| 2026-04-16 | Facebook Marketplace out of scope for car-hunt agent |
