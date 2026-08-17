# Server Setup

OS-level configuration that lives outside Docker — the parts of this homelab a
`docker compose up` cannot restore.

The repeatable parts are scripted (host bootstrap, the UFW ruleset, and a
`host-config` mechanism that symlinks `/etc` files at tracked copies in the repo,
so the repo is the source of truth for host config too). Those scripts, and the
host's real `/etc` files, are the private half of this repo and are not published —
they are full of disk UUIDs, addresses and this specific machine's layout. What
follows is the part that transfers: the decisions, and the reasons behind them.

## Hardware

- Lenovo ThinkCentre M720t, Intel UHD 630 (Quick Sync), DDR4
- boot SSD + 5x HDD in a MergerFS pool + 1x SSD scratch
- a Raspberry Pi elsewhere on the LAN running a second AdGuard Home

## Base install

ubuntu-server LTS. Debian was considered and rejected: the free Ubuntu Pro
subscription gives esm-apps for universe plus livepatch until 2034, and the stack
is distro-portable anyway — worth revisiting only at the next bare-metal rebuild,
never as a project of its own.

Install [docker engine](https://docs.docker.com/engine/install/) and the
[compose plugin](https://docs.docker.com/compose/install/linux/#install-using-the-repository),
then:

```bash
sudo usermod -aG docker "$USER"
# log out and back in for the group to take effect
```

## Storage

### fstab and the MergerFS pool

```bash
sudo mkdir -p /mnt/{hdd1,hdd2,hdd4,hdd5,ssd1,ssd2,storage}
```

**Always mount by UUID, never by `/dev/sdX`.** Host device letters are not stable —
they have reshuffled three times on this box (a USB→SATA shuck, then adding a disk).
The same rule applies to any container that takes a `devices:` list: pin it by
`/dev/disk/by-id/*` (see `scrutiny/compose.yaml`), or Docker will refuse to start the
container the day a letter disappears.

**List the pool branches explicitly** (`/mnt/hdd1:/mnt/hdd2:/mnt/hdd4:/mnt/hdd5`),
not as a `/mnt/hdd*` glob. A glob silently picks up any *empty mountpoint directory*
whose disk failed to mount, and mergerfs then happily writes to the bare directory on
the root SSD — filling it, while the data looks like it landed in the pool. A timer
checks every branch is really mounted, and pages if one is not.

There is no hdd3: it was a USB disk, decommissioned and removed.

**The fstab is not transcribed here.** It lives in the repo and `/etc/fstab` is a
symlink to it. Copies rot: this document used to carry a hand-typed fstab, and within
a month it listed a disk that had been decommissioned a week earlier, used the
dangerous glob above, and was missing a new SSD. A symlink cannot drift.

Two mergerfs facts worth having before you touch a running pool:

- **It is reconfigurable at runtime**, so you almost never need to unmount — which
  would mean stopping everything that touches media. Write the control file instead
  (`setfattr -n user.mergerfs.branches -v … /mnt/storage/.mergerfs`). Always make the
  fstab edit *as well*, or the change reverts silently at the next boot.
- **Branch mode `NC`** (no create) is readable and writable but takes no *new* files.
  That is how one disk is reserved for backups while staying in the pool: with
  `category.create=mfs`, the emptiest disk attracts new writes, which is exactly the
  disk you were trying to keep free.

### Directory structure

```bash
mkdir -p ~/data
mkdir -p /mnt/storage/media-stack/media/{movies,tv}
```

`~/data/<service>/` holds app runtime state; `/mnt` holds bulk media. That split *is*
the backup policy — everything under `~` is backed up, `/mnt` deliberately is not.

The line between "config that belongs in git" and "state that belongs in `~/data`" is
**who writes the file last**, not who created it. A config you author and the container
only reads belongs in the repo. A file the *app* rewrites — its UI saves settings into
it, it stores a password hash — is runtime state wearing a config file's clothes, and in
the repo it produces permanent spurious diffs and tempts you to gitignore it. Which is
the one combination to avoid: a file that is in the repo tree *and* gitignored is in
neither git nor the backups. That is precisely how AdGuard's config survived as a single
copy here for months.

## Network

### Netplan

NIC names change with hardware — check with `ip link`. The netplan file is a
host-config symlink at a tracked copy, with a static address for the server (a DHCP
reservation is not enough when the box *is* the LAN's DNS server: it has to answer on a
known address before it can be asked where anything is). Edit the repo file, then:

```bash
sudo netplan try   # NOT apply — try auto-reverts after 120s if you lose the box
```

Cloud-init must be told to keep its hands off netplan, once per rebuild:

```bash
echo 'network: {config: disabled}' | sudo tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg
```

### DNS

Internal names resolve through two mechanisms, and neither is a public wildcard:

- **AdGuard Home** holds a wildcard rewrite `*.example.com → <server LAN IP>`, so every
  vhost resolves on the LAN with nothing to add per service.
- **Tailnet clients** get there via a Split DNS entry in the Tailscale admin console:
  the internal domain is pointed at the two AdGuard instances, with no global
  nameservers set, so tailnet devices keep their own resolver for everything else and
  only this one domain is diverted. It resolves to the *LAN* address, which works
  because this node advertises the LAN as a subnet route.
- **Cloudflare** holds records only for the handful of genuinely public names.
  `<anything-else>.example.com` does not resolve publicly at all — **that absence is a
  security property, not an oversight.**

So adding an internal service usually means touching no DNS at all.

Two gotchas worth knowing. The server itself runs with `--accept-dns=false`, so the
tailnet's Split DNS does not apply to the host — a host-local `curl` to an internal
vhost needs `--resolve`. And if a name resolves on one side but not the other, that is
split DNS or NAT hairpinning, not the service.

### Resolver redundancy is a three-hop chain, by necessity

The router accepts only **one** DNS server in its DHCP settings, so the textbook "hand
out both resolvers" is not reachable on this hardware. What exists instead: DHCP gives
clients the primary AdGuard and the *router* as secondary, while the router's own
upstream DNS — a separate setting — lists both AdGuards. A client whose primary dies
falls back to the router, which forwards to the survivor. Verified deliberately by
stopping the primary: cache-cold names still resolved in 0.02 s.

The cost to know: while failed over, AdGuard sees every query as coming from the router,
so per-client filtering and per-client stats are blind for the duration.

**Monitor the two resolvers separately, and never through the router.** They exist for
redundancy, so the only question worth asking is whether you still have *both* — and the
router fails over silently, which means a router-only check stays green while you are
down to one resolver.

## Tailscale is a host package, not a container

It ran as a compose stack here originally. Two reasons it moved onto the host, in order
of importance:

1. **Tailscale SSH serves the machine the daemon runs on.** With the daemon in a
   container, `ssh <host>` landed in a stock Alpine image with the state directory
   mounted and nothing else on it.
2. **This node is the LAN's subnet router and an exit node.** As a container, the whole
   house's remote access depended on dockerd starting correctly first.

If you migrate the same way, `systemctl mask tailscaled` *before* installing the
package — its postinst starts the daemon, and a second daemon on a machine where a
container still holds `tailscale0` is a very bad time.

Point the state directory at your backed-up path (here `~/data/tailscale`, via a
systemd drop-in) rather than the packaged `/var/lib/tailscale`. The node key is what
makes the machine the same node; lose it and it re-registers under a new address with
its subnet route and exit-node status unapproved.

Authenticating from scratch, every flag matters — **`tailscale up` resets any pref you
do not name**, so a short command here silently stops the box being a subnet router:

```bash
sudo tailscale up \
     --advertise-tags=tag:server --hostname=<host> \
     --advertise-routes=192.168.0.0/24 --advertise-exit-node \
     --accept-dns=false --snat-subnet-routes=true \
     --stateful-filtering=false --ssh
```

The tag is also what keeps key expiry disabled: an **untagged** subnet router silently
drops off the tailnet roughly 180 days after anyone last thought about it.

Because it now updates via `apt`, the image-update watcher no longer sees it.

## SSH

Key-only auth, ensured by a `/etc/ssh/sshd_config.d/` drop-in setting
`PasswordAuthentication no`. The installer's own cloud-init drop-in may already say the
same; a separate file makes it unconditional.

Note what a hostname reaches once tailscaled is on the host: connections to the
*tailnet* address are answered by **Tailscale SSH**, not by sshd — a browser check-mode
login, not a key. sshd still answers on the LAN address with the key, which is the way
back in when the tailnet is what broke.

## Intel Quick Sync (hardware transcoding)

```bash
ls /dev/dri/          # expect: card0 renderD128
vainfo                # if missing: sudo apt install -y intel-media-va-driver-non-free vainfo
```

Plex and the transcoder both take `devices: ["/dev/dri:/dev/dri"]`. Preserve that
mapping through any change to either.

## Plex: two things that live only in its database

Some settings exist nowhere in the compose file, so nothing in this repo will tell you
they are wrong. These two cost real time to find.

### Library folders outlive the mounts they point at

Both libraries were still configured with paths that had stopped existing in the
container after the bind mounts were consolidated. **Plex does not drop items whose
mount disappears** — it keeps them as unplayable ghosts forever. That left 191 shows in
a 131-show library, with a deleted rip sitting alongside the real file on nearly every
episode of one season.

Removing a location is a `PUT` that **replaces the section's whole config**, so pass
every field back or you will reset the agent, scanner and language along with it:

```bash
curl -X PUT -G "http://127.0.0.1:32400/library/sections/2" \
  --data-urlencode "name=TV Shows"  --data-urlencode "type=show" \
  --data-urlencode "agent=tv.plex.agents.series" \
  --data-urlencode "scanner=Plex TV Series" --data-urlencode "language=en-US" \
  --data-urlencode "location=/data/media/tv" --data-urlencode "X-Plex-Token=$T"
curl -X PUT "http://127.0.0.1:32400/library/sections/2/emptyTrash?X-Plex-Token=$T"
```

### Emptying the trash does not cost you watch history

Worth knowing before a cleanup you are nervous about. Plex keeps view state in
`metadata_item_settings`, keyed by `(account_id, guid)`, with **no foreign key to the
library item or the file**. Removing items, deleting files, or re-adding a library
leaves it untouched, and it re-attaches on its own when the same GUID reappears —
verified after the cleanup above, with 841 history rows and 4234 settings rows intact.

The one real casualty is *semantic*: views recorded while an ordering was wrong point at
whichever episode Plex mislabelled at the time.

### A LAN client can transcode because it came in the wrong way

Plex decides direct-play versus transcode partly from *where it thinks you are*. When
this server was on a bridge network it published only its container addresses to
plex.tv as local connections; those are unroutable from the LAN, so LAN clients failed
them, fell back to the public hostname, and hairpinned in through the reverse proxy.
Plex then saw the connection arriving from the proxy — not from a LAN range — and
classified a laptop in the next room as a **WAN stream**, applying that client's
internet bitrate cap and re-encoding a file it could have remuxed for free.

So when a LAN client transcodes, check **which connection it chose** before touching any
server setting. In the logs, `.../universal/decision?...` carries `location=lan|wan` and
`directPlay=0|1`:

```bash
grep -ao 'universal/decision?[^ ]*' "Plex Media Server.log"
```

Plex tags request sources `(Subnet)` / `(WAN)` / `(Loopback)` — there is **no `(LAN)`
tag**, so grepping for one proves nothing.

The fix was to run Plex on the host network so it advertises a real LAN address, and to
add a `plex.direct` custom connection for the LAN. Consequence: `:32400` becomes a host
listener rather than a docker-published port, so **the host firewall now applies to it**
— including for the containers that reach it through the docker bridge gateway.

## CrowdSec + the nftables bouncer

The CrowdSec *engine* runs in Docker (`crowdsec/`, host network); only the **firewall
bouncer** is a host package, so bans land in nftables ahead of Docker's own chains. The
bouncer's config holds the LAPI key, which is why that one `/etc` file is deliberately
*not* adopted into the repo:

```bash
docker exec crowdsec cscli bouncers add <name> -o raw
# paste into api_key: in /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml, then
sudo systemctl restart crowdsec-firewall-bouncer
```

Two things about the setup are non-obvious:

- **The bouncer in front of Caddy runs in live mode, not streaming** (`disable_streaming`).
  The streaming bouncer wedges Caddy's graceful reload under config churn — and with
  label-driven routing, config churn is normal operation.
- **CrowdSec only sees traffic that goes through Caddy.** A directly published container
  port is outside it entirely.

## Firewall

UFW (iptables-nft) with INPUT `policy drop`, applied from an idempotent, add-only
script. The intended exposure, in shape rather than in detail:

- **WAN:** the reverse proxy's `80` and `443`, plus the game-server port pool. Port 80
  stays open deliberately — scanner traffic on it feeds CrowdSec's `http-probing`
  scenarios, and the resulting bans apply to 443 too. Anything else answering from the
  WAN is a finding.
- **LAN-scoped:** SSH, DNS, SMB, mDNS, Home Assistant and its HomeKit bridge port. The
  HomeKit one is easy to miss: the accessory is *discovered* over mDNS but the
  connection is plain TCP to its own port, so it needs its own allow.
- **tailnet:** the whole interface is trusted.
- **docker bridge:** only the handful of ports host-network services must answer on for
  the proxy and the dashboard to reach them.

Anything in `ufw status numbered` the script did not create is drift, and an audit here
found several `ALLOW Anywhere` rules that should have been source-scoped.

**A ufw rule alone does not constrain a container.** Docker's iptables chains bypass
ufw's INPUT chain for published ports. Not publishing to the host is the stronger
control — services reached through the reverse proxy publish nothing at all, and the two
that a host-local script needs are bound to loopback.

### Isolating untrusted containers needs a chain UFW does not manage

Game servers run untrusted third-party code — mods, plugins, whatever a player uploads.
The rule that contains them **cannot** be a UFW rule: container traffic to a published
port is DNAT'd and *forwarded*, so it never crosses INPUT. It goes in Docker's
`DOCKER-USER` chain (jumped to from the top of `FORWARD`), re-applied at boot by a
systemd unit.

What it does: drop traffic *from* the game network *towards* the LAN, the other Docker
networks and the tailnet. Without it, a game-server RCE reaches every admin UI in the
house — because the reverse proxy's internal allowlist trusts the Docker ranges, and
container traffic arrives SNAT'd from the bridge gateway, indistinguishable from a real
LAN client.

**Return early on ESTABLISHED/RELATED, or LAN players cannot connect.** That exemption
looks decorative and is load-bearing: a LAN player connecting to the published game port
is DNAT'd into the container, so the *reply* is sourced from the game network towards
the LAN and matches the drop rule exactly. WAN players are unaffected, which makes it an
easy break to ship without noticing.

Inbound player traffic, the containers' own egress, and game-to-game traffic are all
untouched.

### A default-port redirect needs the `nat` table

UFW manages `filter` only, so remapping a well-known port to a pool allocation (letting
players keep typing the game's default port) lives in `nat`: a `REDIRECT` for LAN
sources, hooked into **both** `PREROUTING` (other machines) and `OUTPUT` (the server
itself — locally generated packets never traverse PREROUTING, which is also the only way
to test it from the host). The WAN side of the same remap is a port-translating forward
on the router.

Two things about it are deliberate:

- **It targets the published port, not the container.** `REDIRECT` is terminating, so
  Docker's own DNAT never runs and the packet lands on the `docker-proxy` process Docker
  starts for every published port, which relays it in. Ugly but stable — the panel
  rebuilds the game container on *every* start, so a DNAT at the container address would
  be correct only until the next restart.
- **It loses the client's source address.** Userland proxying means those players all
  reach the server as the bridge gateway. If simultaneous local joins ever hit
  "connection throttled", that shared apparent address is why.

No UFW rule accompanies it: the rewrite happens before filtering, so INPUT only ever
sees the destination port that is already allowed.

## Sysctl

Kernel tuning is tracked in the repo and symlinked into `/etc`: IP forwarding (for
Docker and the subnet router), SYN cookies, ICMP-redirect protection, `rp_filter`,
`swappiness=10`, larger UDP buffers, and `fq_codel` for bufferbloat.

> An earlier revision of this document claimed the tuning lived in
> `/etc/sysctl.d/99-homelab.conf`. **That file never existed** — the settings were in
> `/etc/sysctl.conf` all along. Exactly the kind of rot that motivated symlinking host
> config into the repo instead of describing it in prose.

## NFS — disabled

`/etc/exports` is fully commented out, so `nfs-server` and `rpcbind` stay **disabled**.
Left running they advertise the full RPC suite (`nfs`, `mountd`, `nlockmgr`, `status`,
`portmapper`) on `0.0.0.0` for nothing, which is free recon and amplification surface.

```bash
sudo systemctl disable --now nfs-server nfs-mountd rpcbind rpcbind.socket
```

Re-enable only when you actually add an export; scope each one to a host and avoid
`no_root_squash`.

## Docker Swarm — leave it

`docker info` may report **Swarm: active** from some long-ago experiment. **None of the
compose stacks here use swarm** — they are plain compose projects, and the `deploy:`
blocks are only resource limits. Swarm mode opens the control plane (`2377` manager,
`7946` gossip, `4789/udp` overlay) on all interfaces, so if you are not running swarm
services, leave the swarm and let those ports close:

```bash
docker swarm leave --force
```

If you do use it, restrict those three ports to the node addresses and enable
`--autolock` to encrypt the raft store.

## Game servers (Pelican)

Game servers run under [Pelican](https://pelican.dev) (`pelican/compose.yaml`): a panel
plus the `wings` daemon, both behind the reverse proxy. Wings creates one Docker
container per game server **via the host's docker daemon**, which produces the single
most important constraint here: **every path wings hands the daemon must exist on the
host at the same path**, because the daemon resolves it in the host's namespace, not
wings'. Hence the path-identical mounts and the `/etc/pelican` symlink.

Two host-side facts a rebuild has to restore:

```bash
# Symlinks into the backed-up data directory:
#  /etc/pelican      — wings config + the passwd file it mounts into every game container
#  /var/lib/pelican  — wings' backups/archives/state db. The panel rewrites config.yml on
#                      every wings boot, so a config-side backup_directory does NOT stick;
#                      mount the default path and symlink it instead.
sudo ln -s "$HOME/data/pelican/etc" /etc/pelican
sudo ln -s "$HOME/data/pelican/wings/lib" /var/lib/pelican
```

Everything else is bind mounts under `~/data/pelican/` — panel database, wings config,
per-server volumes, in-panel backups. No named volumes, so the backups cover it. The
wings node token lives in its `config.yml`; if lost, regenerate it with
`php artisan p:node:configuration 1` in the panel container.

Game ports come from the panel's allocation pool, and the firewall opens that pool
**once** — creating a server never touches the firewall afterwards. Changing a server's
allocation does not take effect until the server is restarted from the panel: wings
rebuilds the container with the new port bindings then, and rewrites the port in the
game's own config.

**Do not "clean up" the UUID-named containers.** They are the game servers. Manage them
through the panel or `php artisan`, never by editing volumes.

## Deploy

```bash
git clone <this-repo> ~/homelab
cd ~/homelab
cp .env.example .env
$EDITOR .env                          # fill in secrets
sudo bash scripts/bootstrap-host.sh   # packages, /etc symlinks, units, UFW, bouncer, …
make up
```

The bootstrap script is idempotent and sectioned — re-run it whole or per section at any
time; it only adds and fixes, never deletes.

## Scheduled jobs

**No crontab.** Everything scheduled is a systemd timer whose unit file lives in the
repo, so it is in git and survives a rebuild. Most of them push to Uptime Kuma, which
turns "the check did not run" into an alert instead of silence.

| Timer | Schedule | What |
|---|---|---|
| `docker-prune` | weekly | unused images, builder cache, dangling volumes |
| `smart-long-test` | weekly | SMART extended self-test, one disk per week, rotating |
| `mergerfs-mount-check` | every 2 min | every pool branch mounted, and the host-config symlinks still resolve |
| `ddns-check` | every 6 h | the dynamic-DNS records still point at this house: the updater containers are running (early warning) *and* every record resolves — via an **external** resolver — to the real public address (ground truth) |
| `scrutiny-alerting-check` | daily | disk monitoring can still *deliver* an alert: collector fresh, expected disk count present, notify URL on a scheme that actually works, webhook resolves, settings undrifted |
| `healthcheck-sweep` | every 15 min | the repo's ~18 container healthchecks are actually *consumed*: nothing unhealthy, nothing stuck restarting (crash loops never report unhealthy), each finding confirmed by a 30 s re-check |
| `wings-boot-check` | at boot | recreate the game daemon if dockerd's restore dropped its network endpoint — a recurring race, and it hit 2 of 2 reboots before this existed |

The theme in the last three is worth stating on its own: **a check that cannot fail is
not a check.** `scrutiny-alerting-check` exists because disk alerting was silently dead
for two months — the notify URL had been written in a form that returns an error the
sender never surfaces. `healthcheck-sweep` fails if dockerd is unreachable *or* if
healthcheck coverage collapses, because "0 unhealthy containers" is also exactly what
total failure looks like.

Where a monitor is a push target, its heartbeat interval must **exceed** the pusher's
period, or it reports down between every run and becomes the thing crying wolf.

> The docker prune used to be an untracked line in `crontab -e`, and an earlier version
> of this document said it logged somewhere it did not. It is a timer now, and its output
> goes to the journal.
