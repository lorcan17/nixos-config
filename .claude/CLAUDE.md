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

## Observability architecture (OptiPlex)

The monitoring stack is intentionally layered — do not add ad-hoc alternatives:

| Layer | Tool | Module |
|---|---|---|
| Metrics collection | OTEL Collector (`otelcol`) | `otelcol.nix` |
| Time-series storage | Prometheus | `prometheus.nix` |
| Dashboards + alerting | Grafana → ntfy webhook | `grafana.nix` |
| HTTP uptime + heartbeats | Uptime Kuma → ntfy native | `uptime-kuma.nix` |
| Push notifications | ntfy (`alerts` topic) | `ntfy.nix` |

- Netdata runs for lightweight system visibility but is scraped by OTEL Collector, not queried directly for alerting.
- Python pipelines instrument via OTLP push to the Collector when app-level telemetry is needed.
- All alert paths terminate at ntfy `alerts` topic — single routing point.

## Grafana alerts

Alert rules are **fully declarative** — defined in `grafana.nix` under `services.grafana.provision.alerting.rules.settings`. Do not configure alert rules via the UI; they will be overwritten on next rebuild.

Current rules (all in the `Homelab` folder, `homelab` group, 5-minute eval interval):
- `disk-high` — root filesystem usage > 85% for 5m
- `cpu-high` — average CPU > 90% sustained for 10m (10m duration avoids Ollama spikes)
- `memory-high` — memory usage > 85% for 5m

All rules route to the `ntfy` contact point (webhook → `https://ntfy.blue-apricots.com/alerts`) via the default policy. Contact point and routing policy are also provisioned in code.

To add a new alert: add a rule object to the `rules` list in `grafana.nix`. Each rule needs a unique `uid`, a Prometheus `expr` in ref `A`, and a threshold expression in ref `C`.

## Uptime Kuma

Configuration is **UI-only** — no declarative config is supported. Settings live in `/var/lib/uptime-kuma/`.

**HTTP monitors** (check interval 60s, 2 retries) — one per public Caddy vhost:
ntfy, Open-WebUI, Audiobookshelf, Ghostfolio, Netdata, Grafana, Uptime Kuma (self)

**Push heartbeat monitors** — for oneshot systemd pipelines that must phone home on success:
- `questrade-extract` — interval 259200s (72h, covers weekend gap)
- `finance-digest` — interval 259200s (72h, covers weekend gap)

Push URLs are wired into the systemd units via `ExecStartPost` curl calls in `finance.nix`. When adding a new pipeline: create a Push monitor in Kuma UI (259200s interval), copy the push URL, add `ExecStartPost = "${pkgs.curl}/bin/curl -fsS '<url>'"` to the service's `serviceConfig`.

**Notification channel:** ntfy → `https://ntfy.blue-apricots.com/alerts` (configured once in Kuma Settings → Notifications).

No weekend pause option exists in Uptime Kuma — use 259200s (3-day) intervals for Mon-Fri jobs to avoid false weekend alerts. `OnFailure` ntfy push is the primary real-time failure signal; Kuma heartbeat is the "silently stopped running" backstop.

## Caddy TLS

All Caddy vhosts use `import cloudflare_tls` — the snippet is defined once in `caddy.nix` `extraConfig`. Never copy the 3-line `tls { dns cloudflare ... }` block directly into a service module.

## Failure alerting

Critical systemd services declare `OnFailure = "ntfy-alert@%n.service"`. The template service is defined in `alerts.nix`. Add it to any service whose failure should produce an ntfy push.

## Style
- Use `lib.mkDefault` for values that individual machines might override.
- Group related options together with comments.
- Keep module filenames descriptive — `tailscale.nix`, not `ts.nix`.
