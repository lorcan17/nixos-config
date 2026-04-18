# Decisions

> ADR-lite log of architectural and operational decisions for this repo.
> PROJECT_STATUS.md carries a pointer index; this file carries the reasoning.
> Format per entry: Context → Decision → Rationale → Consequences → Revisit if.

---

## 2026-04-17 — Keep Caddy plugin + {$DOMAIN} env var; defer security.acme migration

**Context:** `security.acme` (NixOS-native ACME via lego) was identified as an alternative to the `pkgs.caddy.withPlugins` approach — it eliminates the hash dance and requires no custom Caddy build. However, it requires the domain to be known at eval time, meaning it must appear in the `.nix` files in the public git repo.

**Decision:** Keep the current `pkgs.caddy.withPlugins` + `{$DOMAIN}` environment variable approach. Do not migrate to `security.acme` now. Domain exposure in git is accepted as a known tradeoff for future review.

**Rationale:**
- The Caddy plugin hash is now stable and pinned — the hash dance is a one-time cost per version bump, not an ongoing burden.
- `{$DOMAIN}` keeps the domain out of the public git repo, which is the current preference.
- Migrating to `security.acme` mid-session while debugging TLS would add unnecessary churn.

**Consequences:** `caddy.nix` carries a `pkgs.caddy.withPlugins` override with a pinned hash that must be updated on plugin upgrades. The `caddy-domain` agenix secret remains load-bearing. All Caddy vhosts use `{$CF_API_TOKEN}` substitution for TLS.

**Revisit if:** The repo is made private (domain exposure no longer a concern), the Cloudflare plugin becomes unmaintained, or the hash dance becomes painful again after a forced plugin upgrade.

---

## 2026-04-17 — Caddy TLS via Cloudflare DNS-01 (Let's Encrypt)

**Context:** All Caddy vhosts were using `tls internal` (self-signed CA). Browsers click through the warning, but the ntfy mobile app rejects self-signed certs outright, blocking finance-digest push notifications. A valid TLS solution was needed.

**Decision:** Use ACME DNS-01 challenge via the Caddy Cloudflare DNS plugin (`github.com/caddy-dns/cloudflare`). Caddy is built with the plugin via `pkgs.caddy.withPlugins`; the Cloudflare API token is stored as `caddy-cf-api-token.age` and injected via `EnvironmentFile`.

**Rationale:**
- DNS-01 requires no public port exposure — works entirely over Tailscale with no router port-forwarding.
- Fixes all five subdomains (root, ntfy, chat, abs, ghostfolio) in one change.
- Tailscale Serve was considered but would have required reworking all existing vhosts and loses Caddy's routing flexibility.
- HTTP-01 was ruled out as it requires exposing port 80 publicly.

**Consequences:** Caddy package is now a custom build; hash must be pinned in `caddy.nix` and updated when the plugin is upgraded. `caddy-cf-api-token.age` (env-file format: `CF_API_TOKEN=...`) is a new required secret on OptiPlex. All five vhost `extraConfig` blocks now carry a `tls { dns cloudflare {$CF_API_TOKEN} }` stanza.

**Revisit if:** The Cloudflare DNS plugin stops being maintained, the domain moves to a different registrar, or a public IP becomes available and HTTP-01 becomes simpler.

---

## 2026-04-16 — Transmission RPC inside netns only, no veth bridge to host yet

**Context:** `torrenting.nix` binds Transmission's RPC to `127.0.0.1:9091` inside the `wg-mullvad` netns. The host network (Tailscale, Caddy, future Radarr) cannot reach that address without additional plumbing. Needed an explicit decision on whether to add a veth pair now or defer it.

**Decision:** Defer the host↔netns bridge until Radarr (or an equivalent *arr app) is actually being written. For now, RPC is reachable only via `sudo ip netns exec wg-mullvad transmission-remote ...` or from within the netns itself.

**Rationale:**
- Adding a veth pair adds meaningful complexity to `vpn.nix` (veth creation, IP assignment, routing rules in both directions) for zero present benefit — no consumer of the RPC exists yet.
- The smoke tests (`am.i.mullvad.net` + curl to port 9091 from inside the netns) are sufficient to verify correctness without a bridge.
- When Radarr arrives the options are clear: either run Radarr in the same netns, or add a veth in `vpn.nix`; either choice is a clean, bounded change.

**Consequences:** Caddy cannot reverse-proxy to Transmission's RPC until the bridge exists. Any `*arr` automation tool added before the bridge must also run inside `wg-mullvad` netns (`NetworkNamespacePath`) to reach port 9091.

**Revisit if:** Radarr, Sonarr, or a Caddy vhost for the Transmission web UI is added — at that point, design the veth bridge or confirm the *arr service also joins the netns.

---

## 2026-04-16 — Per-service Caddy vhost blocks (not a shared wildcard matcher)

**Context:** Caddy landed on OptiPlex serving the apex domain, substituting `{$DOMAIN}` from an agenix secret via `EnvironmentFile`. Next step is adding service verticals (Ghostfolio, Open-WebUI, Ollama UI, etc.), each wanting its own subdomain. Needed a default for how subdomain routing is structured before writing the first one.

**Decision:** Each service module declares its own Caddy vhost for its subdomain, e.g. `services.caddy.virtualHosts."ghostfolio.{$DOMAIN}".extraConfig = ...` inside `modules/optiplex/ghostfolio.nix`. No shared wildcard vhost and no central matcher file.

**Rationale:**
- **Matches the Dendritic "one file per feature" rule** already set in CLAUDE.md — adding a service is a single new file, nothing else changes.
- **Grep-friendly debugging:** `grep -r virtualHosts modules/optiplex/` lists every subdomain and where it lives.
- **Clean removal:** deleting a service deletes its module and its routing goes with it — no orphan matcher lines to hunt down.
- **Rejected alternative:** one `*.{$DOMAIN}` vhost with a `@host` matcher routing each subdomain to its upstream. Fewer total lines but every service addition edits a shared file, which is exactly the coupling the module split was done to avoid.

**Consequences:** ~3 extra lines of boilerplate per service (a `virtualHosts."sub.{$DOMAIN}"` block) — accepted as the cost of module self-containment. `modules/optiplex/caddy.nix` stays minimal (just the daemon + agenix secret + firewall); it does not grow as services are added.

**Revisit if:** we ever need per-path routing inside a single subdomain, tight shared middleware (auth, rate-limit) across many services, or Caddy's evaluation of N vhosts starts to hurt on reload — at which point a matcher-based shared block or a separate proxy layer (e.g. Traefik) earns its keep.

---

## 2026-04-16 — agenix on both Mac and OptiPlex

**Context:** Need a single secret-management pattern that works across nix-darwin (Mac) and NixOS (OptiPlex) without introducing a second system.

**Decision:** Use agenix on both hosts. Mac decrypts with the user SSH key (`~/.ssh/id_ed25519`), OptiPlex decrypts with the host SSH key (`/etc/ssh/ssh_host_ed25519_key`). Toggle in `modules/shared/secrets.nix` via an `isDarwin` specialArg.

**Rationale:** Consistent mental model across hosts. agenix encrypts to multiple public keys in a single `.age` file, so one secret can be consumed on both machines without duplicating files.

**Consequences:** Every new secret is declared once in `secrets/secrets.nix` listing who can decrypt, and referenced in `modules/shared/secrets.nix` as an `age.secrets.<name>` attr. Rotating a key means re-encrypting every secret with the new public key.

**Revisit if:** the Mac user key needs to be rotated (agenix-rekey helps), or we grow enough services that sops-nix's multi-file ergonomics become compelling.

---

## 2026-04-16 — Module subdirectories with auto-import (shared / mac / optiplex / wip)

**Context:** The original `flake.nix` manually listed every module per host with a commented-out "layer in after base boot" block. Adding a ready feature meant editing `flake.nix`, which caused us to miss enabling Tailscale after wiring its `authKeyFile`. CLAUDE.md claimed Dendritic/import-tree but that wasn't real.

**Decision:** Split `modules/` into four subdirectories — `shared/` (both hosts), `mac/` (Mac only), `optiplex/` (OptiPlex only), `wip/` (staging, imported nowhere). `flake.nix` uses a small `importDir` helper (`builtins.readDir` + filter) to auto-load each directory into the right host.

**Rationale:** Adding a feature should be a one-file operation. The subdirectory is the routing signal, not a flake.nix edit. WIP gives a safe home to half-built modules without commenting out imports. No new flake inputs required.

**Consequences:** `flake.nix` never changes when adding/promoting a module. Promoting WIP to live = `git mv modules/wip/foo.nix modules/optiplex/foo.nix`. Relative paths inside `modules/shared/*` need `../../` to reach repo-root directories (caught `modules/shared/secrets.nix` during refactor).

**Revisit if:** we want per-namespace module sharing (e.g. a module that could apply to *both* hosts but only on certain conditions), in which case the "real" Dendritic pattern with `flake.modules.nixos.*` / `.darwin.*` namespaces becomes worth the refactor.

---

## 2026-04-16 — Keep Mullvad separate from Tailscale exit nodes

**Context:** Tailscale offers a paid Mullvad exit-node add-on. We need Mullvad anyway for torrent isolation; the add-on raised the question of whether to unify the two.

**Decision:** Run standalone Mullvad WireGuard in a NixOS network namespace (`modules/wip/vpn.nix` → eventually `modules/optiplex/vpn.nix`). Do **not** subscribe to the Tailscale+Mullvad add-on.

**Rationale:**
- **Granularity.** Tailscale exit nodes route the whole device's external traffic; namespaces route a single process. We want only Transmission to use Mullvad — everything else (Ollama, Ghostfolio, Claude API) should go out normally.
- **Leak guarantee.** A namespaced process has no route *at all* if the WireGuard tunnel drops. Tailscale exit-node routing can fall back to the normal interface on failure.
- **Cost and coupling.** Standalone Mullvad is €5/mo flat. The Tailscale add-on requires a paid Tailscale plan on top. And binding torrent-VPN to the overlay network is architecturally odd.

**Consequences:** Two VPN mechanisms on the box with distinct responsibilities: Tailscale for overlay/identity between my devices; Mullvad for per-process outbound anonymity. No centralised VPN admin across devices (acceptable — only OptiPlex needs Mullvad).

**Revisit if:** I want my phone/laptop also tunnelling through Mullvad under central management (at that point, the add-on's multi-device ACLs earn their keep).

---

## 2026-04-16 — Docker accepted as required

**Context:** Ghostfolio, LangAlpha, and Immich are distributed exclusively as Docker / Docker Compose. Initial backlog said "evaluate NixOS-native alternatives first."

**Decision:** Accept Docker on the OptiPlex as a first-class runtime for services whose upstream is Docker-only and whose native packaging would be significant effort.

**Rationale:** Ghostfolio is a Node+Nest+Postgres+Redis stack — porting it to a NixOS module is a moving target. LangAlpha is a Compose-orchestrated multi-container app. The effort of native packaging outweighs the loss of reproducibility for these specific services.

**Consequences:** `modules/optiplex/docker.nix` becomes the single container host. All Docker-only services route through it; don't add per-service runtimes. Prefer NixOS-native whenever upstream offers a module or trivial systemd path (e.g. Paperless-ngx has `services.paperless`, Actual Budget is a simple Node service — both stay native).

**Revisit if:** upstream ships a native module, or Podman on NixOS becomes a cleaner story for declarative container management.

---

## 2026-04-16 — Hybrid LLM: local Hermes 8B + Anthropic API

**Context:** OptiPlex is CPU-only. Heavy agentic loops (LangAlpha's multi-agent research, meeting summarisation, car-listing ranking) are too slow on local inference. Pure-cloud is expensive and defeats some of the homelab point.

**Decision:** Run Nous Research Hermes 8B via Ollama for cheap, high-frequency, low-stakes tasks (article chunking, simple extraction, routine summarisation). Route heavy or multi-step reasoning to the Anthropic API via an agenix-managed key. Select per-task via a config flag in each pipeline.

**Rationale:** Fixed-cost local compute for the volume tasks that would bankrupt cloud usage; pay-per-use API for the tasks that actually need capability. Keeps the "my homelab runs AI" property genuine without the economics of always-cloud.

**Consequences:** Every pipeline needs an explicit model choice. `anthropic-api-key` is a required planned secret. Caching and batching matter — the API bill scales with carelessness.

**Revisit if:** GPU lands in the OptiPlex (changes the local capability ceiling), or Anthropic releases a significantly cheaper tier that shifts the breakpoint.

---

## 2026-04-16 — Torrent isolation via NixOS network namespaces, not a kill-switch

**Context:** Torrenting public-domain content still carries leak risk (peer IP visibility, ISP snooping). The common patterns are iptables kill-switch rules vs. network-namespace isolation.

**Decision:** Run Transmission inside a dedicated `wg-mullvad` network namespace whose only interface is the WireGuard tunnel. Web UI exposed to LAN via a veth bridge.

**Rationale:** Kill-switches are race-prone — iptables rules can have startup-order bugs, and a "block if tunnel down" rule is a soft guarantee. Namespaces give a hard guarantee: if the tunnel is down, the torrent process has **no route at all**. Everything else on the host (Ollama, Ghostfolio, Tailscale) is unaffected — no split-tunnel gymnastics.

**Consequences:** `modules/wip/vpn.nix` defines the namespace primitive; `modules/wip/torrenting.nix` reuses it. Requires `mullvad-wg-config` agenix secret. DNS resolves through Mullvad via `/etc/netns/wg-mullvad/resolv.conf`.

**Revisit if:** NixOS networking dramatically changes (e.g. systemd-networkd reshuffles netns handling), or we move torrenting off the OptiPlex.

---

## 2026-04-16 — TTS default = Kokoro (local); OpenAI TTS as per-book premium opt-in

**Context:** Audiobook + article-to-audio pipelines need a text-to-speech engine. Piper is fast but monotone; ElevenLabs is best-in-class but expensive; OpenAI TTS is a middle ground. Kokoro (~82M params, 2025 open-weights) is recent and CPU-runnable.

**Decision:** Default every pipeline to Kokoro running locally on the OptiPlex. Add a `--voice=openai` flag for per-book premium opt-in, backed by an `openai-api-key` agenix secret.

**Rationale:** Kokoro's quality is a large step up from Piper — listenable for extended sessions. For the daily article briefing (high volume, ephemeral), cloud TTS would burn money. For the occasional novel I actually want to enjoy, OpenAI TTS (~$9 per 100k-word book) is affordable as a deliberate choice, not a default.

**Consequences:** Shared TTS engine (`modules/optiplex/kokoro.nix`) reused across Gutenberg audiobook, article briefing, and any future TTS use. The flag pattern keeps the pipelines identical — only the voice backend changes.

**Revisit if:** Kokoro quality regresses in an update, or a new open-weights TTS (XTTS successor, etc.) clearly surpasses it.

---

## 2026-04-16 — STT = whisper.cpp local (large-v3)

**Context:** Meeting transcription pipeline. Options: local whisper.cpp, hosted OpenAI Whisper API, commercial transcription services.

**Decision:** Run whisper.cpp with the `large-v3` model on the OptiPlex. No cloud STT.

**Rationale:** `large-v3` is near-parity with the hosted API on accuracy for clean-audio meetings. Meeting content is potentially sensitive (business partner discussions, strategy, finances) — local keeps it out of third-party pipelines. Latency isn't critical; transcription happens asynchronously after the meeting.

**Consequences:** Meetings captured on Mac → Syncthing to OptiPlex → whisper.cpp transcribes → Claude API (summary only) → markdown to Obsidian. Only the summary prompt touches the cloud, and it can be reviewed/redacted before sending if a sensitive meeting warrants it.

**Revisit if:** we need real-time transcription (whisper.cpp can, but not on CPU at scale), or whisper loses quality parity with a cloud alternative.

---

## 2026-04-17 — One repo per pipeline (modular, not monolith)

**Context:** Building a finance automation stack (Questrade extract, daily digest). Question was whether to use one shared repo or separate repos per pipeline.

**Decision:** One repo per pipeline. `questrade-extract` owns data fetching, `finance-digest` owns analysis and delivery. Both are flake inputs in `nix-config` (`flake = false`).

**Rationale:** Each pipeline has a distinct job, different deps, different schedules, and different failure modes. Separate repos evolve independently — updating the digest prompt doesn't require touching the extract logic. A future bank PDF extractor, Wealthsimple extractor, etc. all become their own repos writing to the same shared SQLite.

**Consequences:** `flake.nix` needs updating when a new pipeline repo is added (the one case where `flake.nix` must be edited). Each repo is packaged via `python3.withPackages` in `finance.nix` — no uv or Docker at runtime.

**Revisit if:** the number of pipeline repos grows unwieldy, or a shared library emerges that would benefit from a monorepo.

---

## 2026-04-17 — Private GitHub repos for pipelines not worth it

**Context:** `questrade-extract` and `finance-digest` repos were initially created as private. OptiPlex needed to fetch them as flake inputs, which requires auth (GitHub PAT or deploy keys) since Nix uses HTTPS for `github:` inputs.

**Decision:** Make both repos public. Auth complexity (PAT in nix.conf, or deploy key per repo) is not justified.

**Rationale:** The scripts contain no secrets — all credentials are in agenix or `~/.config/questrade/token`. Portfolio data lives in the SQLite DB on OptiPlex, not in the repo. The only "sensitive" content would be ticker names visible in comments, which is not a meaningful exposure.

**Consequences:** Anyone can read the pipeline code. Secrets are never in the repo — enforced by `.gitignore` and agenix.

**Revisit if:** a pipeline repo must embed anything sensitive (e.g. hardcoded account IDs, strategy logic you want private), at which point a GitHub PAT in `nix.settings.access-tokens` is the clean fix.

---

## 2026-04-17 — Questrade refresh token as writable file, not agenix

**Context:** Questrade uses rotating OAuth tokens — each use of the refresh token yields a new refresh token. Needed a storage strategy for this credential.

**Decision:** Store the refresh token at `~/.config/questrade/token` (mode 600) as a JSON file. Each pipeline run refreshes the token and writes the new one back. Not managed by agenix.

**Rationale:** agenix secrets are read-only at runtime (decrypted to a protected file at activation). A rotating credential must be writable by the script. One token file per machine; each machine registers a separate Questrade app so tokens rotate independently.

**Consequences:** Not declarative — the file must be seeded manually once per machine. If the token expires (no run for 30 days), re-seed by generating a new manual auth token in Questrade API Centre and calling the token endpoint once. The script prints clear re-seed instructions on auth failure.

**Revisit if:** Questrade introduces a non-rotating long-lived credential, or we find a clean NixOS pattern for writable secrets.

---

## 2026-04-17 — Caddy TLS strategy for self-hosted services (pending)

**Context:** Caddy is running with `tls internal` (self-signed cert). This works for browser click-through but is rejected by mobile apps (ntfy, etc.) and is non-standard for anything requiring trusted HTTPS.

**Decision:** Pending. Two options under consideration:

1. **DNS-01 challenge** — Caddy requests a Let's Encrypt cert via DNS TXT record. Requires a DNS provider API token as an agenix secret. Works behind Tailscale/NAT with no port exposure. Supported by most providers (Cloudflare, etc.).
2. **HTTP-01 challenge** — Caddy requests a cert via port 80. Requires port 80/443 publicly reachable. Simpler config but exposes the OptiPlex publicly.

**Rationale for deferring:** Neither option is trivially wrong. DNS-01 is cleaner (no public exposure) but requires identifying the DNS provider and obtaining an API token. Chosen to defer rather than rush a decision that affects all services.

**Consequences of deferring:** ntfy push notifications to mobile are blocked. Caddy subdomains only usable in browsers (with click-through warning) or via Tailscale clients that trust the internal CA.

**Revisit if:** ntfy or any other mobile-facing service becomes a priority — at that point DNS-01 is the recommended path.

---

## 2026-04-16 — Facebook Marketplace out of scope for the car-hunt agent

**Context:** Planning an LLM-assisted car-shopping agent. Facebook Marketplace and Craigslist are the two obvious sources.

**Decision:** Craigslist only (via per-search RSS feeds). Facebook Marketplace is explicitly out of scope for any headless scraper.

**Rationale:** Facebook actively fights scraping — session fingerprinting, behavioural rate limits, account bans triggered by non-human access patterns. A "set up an agent and forget it" approach will break within weeks and risk Facebook account suspension. Craigslist offers clean RSS per saved search — trivially parseable, stable for years.

**Consequences:** Agent scope is smaller (Craigslist coverage). If Marketplace access becomes important, the pragmatic path is a browser extension on the Mac that POSTs listings to the OptiPlex, not a headless scraper — real session, real user, one-click ingest.

**Revisit if:** Facebook introduces a Marketplace API, or a stable third-party Marketplace feed emerges.
