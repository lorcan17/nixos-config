# nix-config — Project Status

> Living doc. Update when modules land or plans change. Last updated: 2026-04-22 (Vaultwarden live; Netdata re-added; storage GC automated).

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
| `fmp-api-key` | Mac + OptiPlex | Financial Modelling Prep API |
| `tailscale-authkey` | OptiPlex | Reusable auth key consumed by `tailscaled` at daemon start |
| `mullvad-wg-config` | OptiPlex | WireGuard `.conf` (Sweden exit) consumed by `vpn.nix` |
| `questrade-consumer-key` | Mac + OptiPlex | Questrade OAuth app consumer key (bootstrap only) |
| `anthropic-api-key` | Mac + OptiPlex | Claude API for agentic pipelines |
| `caddy-cf-api-token` | OptiPlex | Cloudflare API token for DNS-01 TLS challenge |
| `open-router-api-key` | Mac + OptiPlex | OpenRouter API key for `or-claude` free-tier model access |

**Retired secrets (`.age` files remain but are no longer decrypted):**
- `caddy-domain` — domain is now a Nix variable in `modules/optiplex/config.nix`
- `domain` — same as above

**Not in agenix (rotating credential):**
- Questrade refresh token — writable file at `~/.config/questrade/token` per machine; rotated automatically on each run

**Planned:**
- `openai-api-key` — premium TTS for audiobooks (per-book opt-in)

---

## Services — OptiPlex

| Service | Module | Status | Notes |
|---|---|---|---|
| Netdata | `netdata.nix` | ✅ Running | netdata.blue-apricots.com; real-time per-process monitoring |
| Dash. | `dash.nix` | ✅ Running | dash.blue-apricots.com; modern system dashboard |
| Ollama | `ollama.nix` | ✅ Running | CPU-only, `0.0.0.0:11434` |
| Tailscale | `tailscale.nix` | ✅ Running | Auth key via agenix; unblocks most other services |
| Mullvad + WireGuard | `vpn.nix` | ✅ Running | `wg-mullvad` netns, Sweden exit; consumers join via `NetworkNamespacePath` |
| Torrenting | `torrenting.nix` | ✅ Running | Transmission inside `wg-mullvad` netns; veth pair bridges host→netns; web UI at torrents.{$DOMAIN} verified; push heartbeat → Kuma |
| Docker | `docker.nix` | ✅ Running | autoPrune enabled; lorcan in docker group |
| Caddy reverse proxy | `caddy.nix` | ✅ Running | Root + subdomain verified |
| Open-WebUI | `open-webui.nix` | ✅ Running | chat.{$DOMAIN} verified |
| Kokoro TTS | `kokoro.nix` | ✅ Running | Docker (CPU); API on 0.0.0.0:8880 (Tailscale-accessible) |
| Audiobookshelf | `audiobookshelf.nix` | ✅ Running | abs.{$DOMAIN} verified |
| Audiobook pipeline | `audiobook.nix` + `audiobook.py` | ⚠ Partial | Pipeline verified end-to-end (Mac → OptiPlex Kokoro → mp3); ~25 min/chunk on CPU = ~7.5h for an 18-chunk article. Unusable at scale. Decision pending: OpenAI TTS vs hardware upgrade (see backlog). |
| Whisper.cpp | `whisper.nix` | ⬜ Not started | STT for meeting transcription |
| Ghostfolio | `ghostfolio.nix` | ✅ Running | Docker Compose + Caddy vhost; uses existing `fmp-api-key` agenix secret |
| ntfy | `ntfy.nix` | ✅ Running | HTTPS via Cloudflare DNS-01; mobile push working |
| questrade-extract | `finance.nix` | ✅ Running | Runs Mon-Fri 16:30 Vancouver; writes to `/var/lib/questrade-extract/questrade.db` |
| finance-digest | `finance.nix` | ✅ Running | Runs Mon-Fri 17:00 Vancouver; mobile notification verified end-to-end |
| OTEL Collector | `otelcol.nix` | ✅ Running | OTLP receiver :4317/:4318; prometheus exporter :8889 |
| Prometheus | `prometheus.nix` | ✅ Running | node_exporter + Netdata + OTEL scrape configs active |
| Grafana | `grafana.nix` | ✅ Running | grafana.blue-apricots.com; disk/CPU/memory alerts provisioned in code → ntfy |
| Uptime Kuma | `uptime-kuma.nix` | ✅ Running | kuma.blue-apricots.com; HTTP monitors + finance heartbeats configured; ntfy wired; Transmission push monitor active |
| Jellyfin | `jellyfin.nix` | ✅ Running | media.blue-apricots.com; Movies → /var/lib/media/movies, TV → /var/lib/media/tv |
| Byparr | `byparr.nix` | ✅ Running | Cloudflare bypass proxy for Prowlarr; localhost:8191 |
| Prowlarr | `prowlarr.nix` | ✅ Running | Indexers configured; synced to Radarr + Sonarr |
| Radarr | `radarr.nix` | ✅ Running | Transmission client wired; category subdir /var/lib/transmission/Downloads/radarr; root /var/lib/media/movies |
| Sonarr | `sonarr.nix` | ✅ Running | Transmission client wired; category subdir /var/lib/transmission/Downloads/sonarr; root /var/lib/media/tv |
| Jellyseerr | `overseerr.nix` | ✅ Running | seer.blue-apricots.com; Jellyfin + Radarr + Sonarr connected |
| AudioBookRequest | `audiobookrequest.nix` | ✅ Running | books.blue-apricots.com; Prowlarr + ABS wired; limited by lack of private tracker — public indexers sparse for audiobooks |
| Vaultwarden | `vaultwarden.nix` | ✅ Running | vault.blue-apricots.com; Bitwarden-compatible |
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
- [x] **Mullvad + WireGuard (vpn.nix)** — WireGuard config from agenix; introduces the `wg-mullvad` netns that `torrenting.nix` will reuse. _(landed 2026-04-16, verified via am.i.mullvad.net)_
- [x] **Docker (docker.nix)** — deployed. _(landed 2026-04-17)_
- [x] **Caddy reverse proxy** — subdomain routing once Tailscale + domain are in. _(verified 2026-04-16)_

### Tier 1.5 — Dev workflow (blocks fast iteration on all Python pipelines)
- [ ] **WIP project dev workflow** — current loop (edit → commit → flake update → rebuild → test) is too slow for Python iteration. Decision needed on: (1) Syncthing `~/projects/` Mac → OptiPlex so local edits are live without committing; (2) `--override-input` to point NixOS at the synced local path instead of GitHub; (3) gitignored `.env` file per project for personal context (account nicknames, risk preferences, prompt tuning) that never hits git. Direct `python3 -m ...` execution on OptiPlex works as an interim workaround. See DECISIONS.md backlog.

### Tier 2 — First verticals (share TTS + job-runner scaffolding)
- [ ] **Gutenberg → audiobook pipeline** — `make-audiobook --gutenberg ID`; Kokoro TTS → `.m4b` with chapters + cover + metadata → Audiobookshelf. Module written; needs `nixos-rebuild switch` on optiplex then first test run.
- [ ] **Article → audio briefing** — `make-audiobook --url URL`; same pipeline, outputs `.mp3` to podcasts dir. Module written + rebuild done. **Blocked on TTS speed** — ~25 min/chunk on Kokoro CPU; a 18-chunk article takes ~7.5h. Decision needed (see below).
- [ ] **Meeting transcription + summary** — Drop audio file into a watched folder (Syncthing or scp); OptiPlex: Whisper.cpp transcribes → Claude API summarises → delivers text summary (email or push). Optional second pass: Kokoro TTS reads the summary back as an audio file. Mac doesn't need to be on — OptiPlex runs the whole pipeline headlessly. Needs: Whisper.cpp module, Claude API agenix secret, delivery mechanism (email vs push vs Obsidian). Needs more thought before building.
- [x] **Torrenting (torrenting.nix)** — Transmission running in `wg-mullvad` netns; web UI at torrents.{$DOMAIN}. _(landed 2026-04-18)_

### TTS speed decision (blocks audiobook + article pipelines)

Kokoro on the OptiPlex CPU is ~25 min/chunk = ~7.5h for a typical long-read article. Three options to weigh:

| Option | Cost | Quality | Latency |
|---|---|---|---|
| **OpenAI TTS** (`tts-1`) | ~$0.015/1k chars → ~$0.40/article, ~$3–8/book | Good | Seconds |
| **OpenAI TTS** (`tts-1-hd`) | ~$0.030/1k chars → ~$0.80/article, ~$6–15/book | Excellent | Seconds |
| **Hardware upgrade** (used GPU workstation or NUC with iGPU) | $200–600 one-time | Local/private | Minutes |

Break-even on hardware vs OpenAI TTS: at $400 for a used machine and $0.40/article, that's ~1000 articles before hardware pays off. At $3/book, ~133 books.

Decision: defer until audiobook use frequency is known. Default to OpenAI TTS `tts-1` as a per-run opt-in (`--openai` flag) rather than committing to hardware upfront.

### Tier 2.5 — Priority next
- [x] **Vaultwarden** — self-hosted Bitwarden-compatible password manager; official Bitwarden clients on Mac, Android, browser extensions all connect to it; `services.vaultwarden` NixOS module available _(landed 2026-04-22)_
- [ ] **Secure Vaultwarden** — set `SIGNUPS_ALLOWED = false` in `vaultwarden.nix` once both accounts are registered.

### Tier 2.6 — Media stack UI config
- [x] **Prowlarr indexers** — configured with Byparr for Cloudflare bypass; synced to Radarr/Sonarr _(2026-04-18)_
- [x] **Radarr** — Transmission client wired; category subdirs created with group-write; root /var/lib/media/movies _(2026-04-20)_
- [x] **Sonarr** — Transmission client wired; root /var/lib/media/tv _(2026-04-20)_
- [x] **Jellyfin library update** — Movies → /var/lib/media/movies, TV → /var/lib/media/tv _(2026-04-20)_
- [x] **Jellyseerr** — running at seer.blue-apricots.com; Jellyfin + Radarr + Sonarr connected _(2026-04-20)_
- [x] **AudioBookRequest** — running at books.blue-apricots.com; Prowlarr + ABS wired _(2026-04-20)_
- [ ] **Stremio + Torrentio** — install Stremio + Mullvad on Onn Android TV box; add Torrentio addon
- [ ] **Storage expansion** — 512GB will fill fast with movies/TV; plan NAS or external drive before it becomes urgent
- [ ] **Private tracker seeding problem** — Mullvad discontinued port forwarding 2023-07-01; Transmission in wg-mullvad netns cannot accept inbound connections, making seeding on private trackers (e.g. MyAnonamouse) impossible. Options: (1) switch VPN provider to one with port forwarding (AirVPN, ProtonVPN); (2) split-tunnel MAM traffic outside the netns; (3) accept public-only trackers

### Tier 3 — Finance stack
- [x] **Ghostfolio** — running; `$FMP_API_KEY` wired via agenix. _(landed 2026-04-17)_
- [x] **questrade-extract** — daily systemd timer pulls balances + positions from Questrade API → SQLite at `/var/lib/questrade-extract/questrade.db`. Repo: `github:lorcan17/questrade-extract`. _(landed 2026-04-17)_
- [x] **finance-digest** — daily systemd timer reads DB → Claude analysis → ntfy push. Repo: `github:lorcan17/finance-digest`. Blocked on ntfy TLS. _(landed 2026-04-17)_
- [ ] **Caddy TLS** — DNS-01 via Cloudflare wired in code. Needs: (1) create `cf-api-token.age` secret, (2) fix plugin hash after first failed build, (3) `nixos-rebuild switch`.
- [ ] **LLM portfolio updater** — Python job: broker CSV/PDF from a Syncthing folder → Claude API extracts activities → POST to Ghostfolio `/api/v1/order`.
- [ ] **Project Foundry — finance data lake** — DuckDB medallion architecture (bronze/silver/gold) + dbt transformations + embedding pipeline. See [FOUNDRY.md](./FOUNDRY.md) for full spec. Repos: `questrade-extract` (existing), `bank-cc-extract` (PDF parser complete), `finance-lake` (dbt + embed-enrich, not started). Key build order: (1) DuckDB schema + permissions NixOS module, (2) finance-lake dbt project with transfer matching + merchant normalisation, (3) OpenWebUI SQL tool provisioner.
- [ ] **LangAlpha** — multi-agent equity research stack (LangGraph + MongoDB + Playwright + paid APIs, ~$30–80/mo realistic). Defer until Foundry is stable.

### Tier 4 — PKM + household
- [ ] **Paperless-ngx** — first-class `services.paperless` NixOS module. OCR paper docs into the PARA workflow.
- [ ] **Actual Budget** — self-hosted YNAB alternative; trivial Node systemd service.
- [ ] **Immich** — self-hosted photos. Docker; community Nix module lags upstream.
- [ ] **Open-WebUI** — browser frontend for Ollama.
- [ ] **Monitoring** — Prometheus + Grafana, or Netdata.

### Tier 5 — Reliability / ops
- [ ] **Reboot strategy (reboot.nix or ops runbook)** — OptiPlex is not always-on; services that hold state (Transmission, Ghostfolio Postgres/Redis, VPN netns) need to survive a clean reboot gracefully. Strategy to cover: (1) `wantedBy = ["multi-user.target"]` + `after/requires` ordering for netns-dependent services; (2) verify Transmission resumes correctly after `wg-mullvad` comes up; (3) decide whether a `systemd-networkd-wait-online` or `network-online.target` dependency is sufficient; (4) document manual recovery steps for a dirty shutdown; (5) optionally add a boot-time health check that pings Tailscale + Mullvad before declaring the system ready.

### Tier 6 — Experiments / someday
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

---

## Decision Log

Full ADR-lite entries with reasoning live in [DECISIONS.md](./DECISIONS.md). This is the index:

| Date | Decision |
|---|---|
| 2026-04-22 | No third-party budgeting app (Sure/Firefly) — all features replicated in dbt; DuckDB is sole SoR |
| 2026-04-18 | Netdata removed; node_exporter + OTEL Collector sufficient; web UI unfixable |
| 2026-04-17 | Monitoring stack: OTEL Collector → Prometheus → Grafana → ntfy; Uptime Kuma alongside |
| 2026-04-17 | Keep Caddy plugin + {$DOMAIN} env var; defer security.acme migration |
| 2026-04-17 | Caddy TLS via Cloudflare DNS-01 (Let's Encrypt) |
| 2026-04-16 | Transmission RPC inside netns only, no veth bridge to host yet |
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
