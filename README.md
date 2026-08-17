# 🏠 Homestack

A self-hosted homelab running on a single Lenovo ThinkCentre M720t, orchestrated
entirely with Docker Compose and a thin `make` wrapper. Each service is an
independent compose project; everything is reverse-proxied through Caddy with
automatic TLS, monitored, and backed up offsite.

> This is a public showcase of my homelab configuration. Secrets live in
> gitignored env files (templates are provided), and a few private services are
> omitted. Domains are shown as `example.com` — swap in your own.

## ✨ Highlights

- **No Caddyfile** — reverse-proxy routing is configured purely via Docker labels
  using [`caddy-docker-proxy`](https://github.com/lucaslorentz/caddy-docker-proxy),
  with TLS via the Cloudflare DNS challenge (no exposed ports for certs).
- **One make target per service** — `make up-caddy`, `make logs-adguard`,
  `make restart-homepage`, … plus aggregates (`make up`, `make pull`, `make status`).
- **Clean data separation** — compose files and small configs live in git; app
  state, databases, and media live outside the repo and are never committed.
- **Defense in depth** — Tailscale for remote access, AdGuard Home for DNS-level
  filtering, CrowdSec for intrusion detection, minimal WAN exposure.
- **Offsite backups** — the whole home directory (app state *and* this repo) is
  backed up nightly by Borgmatic to two destinations: a local disk and a Hetzner
  Storage Box, encrypted client-side, with a dead-man's-switch ping so a backup that
  silently stops running becomes an alert.

## 🧱 Architecture

```
                         ┌─────────────┐
        Internet ───────▶│  Cloudflare │  (DNS + DNS-01 challenge)
                         └──────┬──────┘
                                │
                         ┌──────▼──────┐
                         │    Caddy    │  reverse proxy, automatic TLS
                         │ (labels →   │  *.example.com
                         │  upstreams) │
                         └──────┬──────┘
                  ┌─────────────┼───────────────┐
            ┌─────▼────┐  ┌─────▼─────┐   ┌──────▼──────┐
            │  media   │  │ homepage  │   │  adguard…   │  + many more
            │  (Plex)  │  │ dashboard │   │  (LAN IP)   │
            └──────────┘  └───────────┘   └─────────────┘

  Remote access via Tailscale · Intrusion detection via CrowdSec
```

### Networking

| Network | Type | Purpose |
|---|---|---|
| `proxy_network` | bridge `172.20.0.0/16` | Service ↔ Caddy reachability |
| `lan_macvlan` | macvlan `192.168.0.240/28` | Created, currently unused |
| `network_mode: host` | — | AdGuard, CrowdSec, Home Assistant, Samba, Plex |

The rule of thumb for that last row: anything that advertises its own reachable
address to a third party, or relies on broadcast/discovery, wants host networking —
everything else is better off on a bridge with no published ports at all.

## 📦 Services

| Service | Role |
|---|---|
| **Caddy** | Reverse proxy + automatic TLS (label-driven, no Caddyfile) |
| **Tailscale** | Mesh VPN, subnet router and exit node — a host systemd unit, not a container ([why](docs/setup.md)) |
| **AdGuard Home** | Network-wide DNS + ad/tracker blocking (primary + Pi replica) |
| **Plex** (`plex/`) | Media server with hardware transcoding (Intel Quick Sync) |
| **Homepage** | Single-pane dashboard with live service widgets |
| **Uptime Kuma** | Uptime/status monitoring |
| **Scrutiny** | Disk S.M.A.R.T. health monitoring |
| **CrowdSec** | Crowd-sourced intrusion detection + firewall bouncer |
| **Borgmatic** | Encrypted, deduplicated offsite backups |
| **Diun** | Docker image update notifications |
| **Samba** | SMB file sharing + Time Machine target |
| **Home Assistant** | Home automation |
| **Bitcoin node** | Pruned Bitcoin full node |
| **Snowflake** | Tor Snowflake proxy (censorship circumvention) |
| **Pelican** | Game-server panel + `wings` daemon (one container per server, started on demand) |

## 🗂️ Repo layout

```
homelab/
├── Makefile              ← orchestration (one project per service)
├── .env.common           ← shared non-secret constants (TZ, PUID, PGID) — committed
├── .env.example          ← template for gitignored .env (all secrets)
├── docs/
│   └── setup.md          ← OS-level setup: storage, networking, firewall, the traps
└── <service>/
    ├── compose.yaml      ← the service definition
    └── config/           ← small bind-mounted configs (where applicable)
```

App data (`~/data/<service>/`), media, and downloads live **outside** the repo
and are intentionally not committed.

## 🚀 Getting started

```bash
# 1. Provide secrets (never committed)
cp .env.example .env && $EDITOR .env

# 2. Bring everything up (creates Docker networks first)
make up

# Per-service control
make up-caddy        # start one service
make logs-adguard    # tail logs
make restart-homepage
make status          # list running containers
make help            # all targets
```

## 🔐 Secrets & data — what's in git and what isn't

| What | Where | In git? |
|---|---|---|
| Compose files + small configs | `<service>/` | ✅ |
| Shared non-secret constants | `.env.common` | ✅ |
| Secrets (Cloudflare token, app credentials, backup passphrase) | `.env` | ❌ gitignored |
| App runtime data (DBs, caches, metadata) | `~/data/<service>/` | ❌ |
| Media & downloads | `/mnt/storage/` | ❌ |

## 🖥️ Hardware

- **Server**: Lenovo ThinkCentre M720t — Intel UHD 630 (Quick Sync hardware
  transcoding), MergerFS storage pool across multiple drives.
- **Backup DNS**: Raspberry Pi running a second AdGuard Home instance.
- **Storage**: run-to-failure JBOD — no RAID, no parity. Media is replaceable and
  treated that way; the one irreplaceable directory on the pool is pinned to a single
  disk so a drive death cannot take a share of everything.

---

*Generated as a sanitized public mirror of a private homelab repo.*
