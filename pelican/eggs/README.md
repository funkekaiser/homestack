# Pelican eggs authored here

Eggs the panel needs that don't exist upstream. Import via **Admin → Eggs →
Import Egg**; re-importing an edited file with the same `uuid` updates the egg in
place rather than creating a second one.

Everything else on this node uses a stock egg from
[`pelican-eggs`](https://github.com/pelican-eggs) — add one here only when
upstream has nothing.

---

## `egg-bannerlord-coop.json` — Bannerlord Coop dedicated server

The co-op **campaign** mod ([workshop item
3770450698](https://steamcommunity.com/sharedfiles/filedetails/?id=3770450698)),
not TaleWorlds' native PvP server. The stock
`pelican-eggs/games-steamcmd/mount_blade_II_bannerlord` egg cannot host it: that
one runs `DedicatedCustomServer.Starter.exe` (app 1863440) for skirmish/siege
modes, and the Coop module declares `SingleplayerModule=true` +
`DedicatedServerType=none`, so the native headless starter will not load it.

### What the server actually is

Confirmed from the mod's own setup video (2026-07-30). The workshop item unpacks
to `steamapps/workshop/content/261550/3770450698/`, and the server lives in
`DedicatedServer/`:

```
engine/                  bundled TaleWorlds engine + assemblies
server-data/             saves ("Game Saves"), logs/coop-server-*.log
archive-layout.json      1 KB
BannerlordCoopServer.exe 31.8 MB
release-info.txt         3 KB
server-config.json       3 KB, JSONC (comments + trailing commas allowed)
```

Its banner on boot settles the two questions that decide feasibility:

```
Bannerlord Coop  —  Dedicated Server
  save : saveauto1.sav  (server-config.json)  [new world from default_new_game.sav]
  port : 7210 (EU)   coop clients join on UDP 4200
  pass : none ("password" in server-config.json)
  data : ...\DedicatedServer\server-data
  .net : bundled (no system .NET required)
[launcher] campaign load takes ~30-60s and prints a lot of engine diagnostics — normal, not an error.
[launcher] ready when you see: [DedicatedServer] SERVING  ·  'help' lists commands  ·  F10 stops
```

- **Self-contained.** Bundled .NET, own `engine/` — no Bannerlord install, no
  system runtime. It is still a **Windows** binary (the module identifies as
  `DedicatedServer.Windows`), hence Wine.
- **Steam is optional.** `"steam": true` advertises the server in the public
  lobby and relays traffic through Steam — that mode needs a logged-in Steam
  client on the same machine, which a container will not have. `"steam": false`
  means **direct connect, UDP 4200 only**, which is the mode this egg targets.
- Config keys seen: `saveName`, `autosaveMinutes` (5), `password`, `logFile`,
  `steam`, the `difficulty` block, and diagnostics toggles. It is JSONC, so the
  panel's JSON config parser would eat the comments — the egg deliberately
  manages **no** config file. Edit `server-config.json` in the file manager.

### Acquisition — the awkward part

The workshop item is 6.08 GB and **cannot be fetched anonymously**; verified in
the same yolk image an egg install runs in:

```
$ steamcmd +login anonymous +workshop_download_item 261550 3770450698 +quit
ERROR! Download item 3770450698 failed (Failure).
```

So the install script has two paths: SteamCMD with an account that owns
Bannerlord (`STEAM_USER`/`STEAM_PASS`/`STEAM_AUTH`), or a manual upload. The egg
never bundles or re-hosts the files, and neither should any published copy of it
— see the licensing note below.

**Better source, found 2026-08-15: Nexus Mods.** The team publishes the server
itself as a versioned optional file on
[mod 11879](https://www.nexusmods.com/mountandblade2bannerlord/mods/11879?tab=files),
which is a straight improvement on the Workshop route: **4.1 GB instead of 6 GB**
(server only, no client assets), and *labelled with a version that matches the
client file*, which is the whole answer to the host/client mismatch problem.
Their file list, from the unauthenticated v2 GraphQL API
(`api.nexusmods.com/v2/graphql`, `{ modFiles(modId: 11879, gameId: 3174) }` —
the HTML pages are Cloudflare-blocked, the API is not):

| fileId | name | version | size | date |
|---|---|---|---|---|
| 65306 | Coop (client) | 0.1.2-2 | 7.2 MiB | 2026-08-14 |
| **65307** | **DedicatedServer** | **0.1.2-2** | **4186 MiB** | **2026-08-14** |
| 65032 | DedicatedServer | v1 | 4186 MiB | 2026-08-10 |

It still cannot be scripted. Nexus downloads need an authenticated session; the
v1 API's `download_link.json` hands back a URL only for **premium** accounts,
free accounts have to click the slow-download page for a short-lived token, and
this mod sets `directDownloadEnabled: false`, which kills even the Vortex/nxm
path. So it is the same shape of blocker as Steam credentials — fine for a
private egg with the operator's own API key, still not publishable.

There is **no Linux build** among those files, consistent with the Workshop
package being Windows-only.

**What we run is older than what is published.** Our `release-info.txt` says
built 2026-08-09 and `engine/Modules/Coop/SubModule.xml` reads `v0.1.2`; Nexus
is on `0.1.2-2` from 2026-08-14. Since the server SHA-pins its paired Coop
assemblies and `ModuleValidator` compares community-module versions in both
directions, a client that has auto-updated from the Workshop may already refuse
to join. Updating is: download 65307, replace `DedicatedServer/`, leave
`coop-data/` alone — which is exactly why `--data-dir` points outside the install
folder.

### What is and isn't open, exactly

Worth being precise, because "closed source" is the wrong word and it changes
what may be redistributed:

- **The mod is source-available, not open source.** `BannerlordCoop` is a real,
  busy repo (~300 issues, ~40 PRs) with the whole mod in it —
  `source/Coop.Core`, `GameInterface`, `Common`, and the co-op server *logic*
  in `Coop.Core/Server/CoopServer.cs`. But `LICENSE` is the "BannerlordCoop
  Source Available License": viewing, reference, security review and
  contribution only, and explicitly **no copying, publishing, distributing,
  sublicensing or reuse in another project** without written permission.
  `NOTICE.md` records the switch away from MIT on **2026-06-17**; versions
  released before that keep their MIT terms.
- **The thing we actually run is not in that repo.** A full recursive tree of
  `development` (4698 paths, untruncated) contains no `BannerlordCoopServer`
  project, and a code search finds no `@DS@`, no `--data-dir`, no launcher
  source. `source/ServerConsole` is a *mission-test* server, not this. The
  repo's `AGENTS.md` names `Bannerlord.DedicatedServer` as a separate authorized
  project, and that repo 404s under this org — so the launcher, the
  `DedicatedServer.Windows` module and the boot-time SHA-256 verification live
  somewhere non-public.
- **Redistribution is blocked twice over anyway.** Even under the old MIT terms,
  `DedicatedServer/engine/` is TaleWorlds' engine plus ~5.5 GB of their asset
  packages. That was never ours to ship, whatever the mod's licence says.

### There is a native Linux server — it just isn't shipped

Written down because I had this wrong, and because the repo contains a
`linux-only-runmefirst.sh` that looks like the evidence but isn't:

- **`linux-only-runmefirst.sh` is a developer helper.** It waits for you to start
  the Bannerlord launcher, finds the process, and symlinks `./mb2` at the game
  directory so the `.csproj` files can resolve TaleWorlds' assemblies. Its
  Windows twin is `runmefirst.cmd` → `prepare-links.ps1`. It is about *building
  the mod* on a Linux workstation, nothing to do with hosting.
- **The real evidence is issue
  [#2843](https://github.com/Bannerlord-Coop-Team/BannerlordCoop/issues/2843)**,
  filed by the repo's top contributor and closed the same day: *"Linux dedicated
  server aborts when a co-op battle concludes"*. Its environment block reads
  "Native Linux dedicated server, **no Wine** · .NET runtime 6.0.36, x64 ·
  Dedicated-server repository commit `677f335`", and the body has Docker
  restarting it under a restart policy. It also refers to "the TaleWorlds Linux
  dedicated runtime" — TaleWorlds *does* ship a Linux headless build for native
  multiplayer, so the engine is not Windows-only the way I assumed.
- **`DedicatedServer.Linux` is a first-class module ID.** `ModuleValidator`
  exempts anything prefixed `DedicatedServer.` from client/server module
  matching, and `ModuleValidatorTests` carries paired
  `…WhenOnlyServerHasDedicatedServerWindowsModule` and
  `…DedicatedServerLinuxModule` cases.
- **But the workshop item ships Windows only.** `release-info.txt` is headed
  "Bannerlord Coop Dedicated Server (Windows x64)", and the install's
  `engine/Modules/` holds exactly `Coop, DedicatedServer.Windows, Native,
  SandBox, SandBoxCore`. The Linux build lives in the private dedicated-server
  repo. So Wine is the right call *today*, not forever — and the upstream ask
  below is "publish the Linux build you already run", not "please make one".

### Verified under Wine, 2026-08-15

Ran the real `BannerlordCoopServer.exe` in `ghcr.io/parkervcp/yolks:wine_latest`
(Wine 11.0) before writing any of it into the panel:

- **It works headless.** `[DedicatedServer] SERVING — coop server up, waiting for
  clients` after a **52 s** cold boot building a fresh world — *faster* than the
  same build on the Windows box it came from (76 s). UDP 4200 open inside the
  container (`dotnet.exe`), autosave wrote the world in 1.6 s.
- **`xvfb-run` hangs it** — Xvfb starts, Wine never launches, 0 % CPU forever.
  Start Xvfb explicitly and pass `DISPLAY=:0`; that is what the egg does.
- **There is NO clean shutdown through the panel.** I wrote the opposite here
  first, on the strength of typing `stop` into an interactive container; through
  wings it has never worked. See the section below — this is the one real defect
  in the deployment.
- **`--data-dir "Z:\home\container\coop-data"` works** (Wine path form), and puts
  `server-config.json`, `Game Saves/` and `logs/` where the file manager can
  reach them instead of six levels deep in the Wine prefix.
- **Done-marker**: match `phase":"serving"` from the machine-readable
  `@DS@{"ev":"state","phase":"serving",...}` line — *not* the word `SERVING`,
  which also appears in the banner's "server is READY when you see:" hint 52
  seconds too early.
- **Idle cost: ~1.4 cores and 1.25 GB with zero players.** The campaign keeps
  ticking regardless, so this is a start-it-to-play server, not a 24/7 one.
- The `Cannot load: 0Harmony.dll / Common.dll / SandBox.dll / GameInterface.dll /
  Steamworks.NET.dll` errors are **noise** — the engine probes
  `engine\bin\Win64_Shipping_Server\` first and the real copies live in
  `engine\Modules\Coop\bin\Win64_Shipping_Server\`. The same lines appear in a
  successful Windows run.
- **The install directory must be writable.** `AutoSyncPatcher.PatchAll()` writes
  `engine/Modules/Coop/bin/Win64_Shipping_Server/AutoSyncExport/AssemblyInfo.cs`
  on every boot; mount it read-only and the campaign load dies with
  `UnauthorizedAccessException` right after `HostSaveGame(...) PatchAll`. Found
  by mounting it `:ro` in a test container. Nothing to change in the egg — wings
  gives the server its own writable volume — but it rules out ever sharing one
  read-only install between servers.
- Only `DedicatedServer/` is needed; the rest of the workshop item is client-side.

### Readable console XOR console commands — pick one (2026-08-15)

The launcher has a `--no-tui` flag. It is in `BannerlordCoopServer.exe --help`
and nowhere else: `release-info.txt` documents only `--data-dir`, so the flag
list is invisible unless you ask for it. Worth running `--help` on any binary
before designing around its behaviour, which I did not.

```
--no-tui   plain console output (no log/players/command panes);
           automatic when stdout or stdin is redirected
-p, --port <n>   port the ENGINE is started as a custom server on
                 (default: 7210) — NOT the port players connect to
--no-watchdog    skip the engine's Watchdog.exe crash collector
```

That also explains last night's `| cat`: it was not defeating the TUI, it was
tripping the documented "stdout is redirected" auto-detection. The egg now says
`--no-tui` explicitly and the pipe is gone. Verified through wings, not by hand:
one `phase":"serving"` marker, **zero** cursor-addressing or clear-screen
sequences in the container log, panel state `running`, UDP 4200 bound.

**The catch is that "no command panes" includes the command reader.** In plain
mode the server prints but does not listen:

- Panel `stop`: wings acquires the power lock, sends `stop`, and nothing happens.
  The server runs until wings gives up and SIGKILLs it (exit 137). Reproduced
  both with `| cat` and with `--no-tui`.
- Typed by hand over a real pty (`docker attach` on a pty, so input echoes back
  and is definitely arriving): neither `stop` nor `help` produces any response.
- `kill -INT` on the Wine process: ignored. The banner's "Press Ctrl+C to stop"
  is a Windows console event that Wine does not synthesise from a Unix signal.

The two modes are exclusive, and neither is fully usable:

| | panel console readable | done-marker on stdout | console commands |
|---|---|---|---|
| TUI (default) | no, escape-code soup | no | yes |
| `--no-tui` | yes | yes | **no** |

`--no-tui` is still the right choice: without the done-marker the panel never
leaves "starting", which breaks the panel outright. The cost is that **stopping
this server is always a kill**. Mitigation is `autosaveMinutes: 5` plus the two
retained generations (`saveauto1.backup1`, `.backup2`) — so worst case is five
minutes of campaign, and the crash-safety of a killed save is upstream's problem
(cf. their #2593, save corruption after an unclean restart). Prefer stopping
between battles.

This is the sharpest thing to put upstream: not "please add a plain-log mode",
which exists, but "please keep reading stdin when the panes are off".

### The port: fixed on the server, free on the client

**The server side is fixed.** `release-info.txt` states "ALL server settings live
in server-config.json" and enumerates them — `saveName`, `autosaveMinutes`,
`password`, `logFile`, `steam` — with no port among them. This build binds UDP
**4200** and nothing in the shipped files changes that. (The mod's own
`deploy/mod-config.default.json` claims "ports … live in the dedicated server's
own `server-config.json`"; that is aspirational — the key does not exist.
`Coop.Core`'s `NetworkConfig.Port` is a settable property, so the plumbing is
there but unexposed by the launcher.)

**The client side is not fixed** — this is the part I had wrong.
`GameInterface/Services/UI/CoopConnectMenuVM.cs` renders an IP box *and* a Port
box, hinted "The port the co-op server listens on. Leave 4200 unless the host
changed it." So the Minecraft remap (router forwards WAN 25565 → pool 27003)
*does* apply in principle: the router may forward any WAN port to
`192.168.0.10:4200` and players type `host:port`.

What that does **not** change:

- **The allocation is still 4200.** wings publishes `ip:port:port` with no remap
  of its own, and the process binds 4200 inside the container.
- **Still only one such server per host**, since every one of them wants 4200.

It also doesn't change UFW, but not for the reason I first wrote here. I claimed
UFW "still needs" the `4200/udp` rule because it matches the host destination
port. It doesn't need it at all: `docker inspect` shows wings publishing the
allocation as a **docker port binding** (`4200/udp → 0.0.0.0:4200`), and
docker-published ports bypass UFW entirely — the invariant already stated at the
top of `scripts/ufw-rules.sh`. The rule is not load-bearing. It stays anyway,
for exactly the reason the `27000:27015` pool rules do: that script is the
intended exposure written as code, and a game port missing from it reads as
"this isn't meant to be reachable".

So the WAN port is a free choice and we kept 4200 for simplicity; moving it into
27000–27015 would only hide it from scanners, not remove the bespoke UFW rule.
It is still the first per-game exception since V Rising moved into the pool.

One footnote: the mod's `deploy/Server Instructions.md` tells hosts to forward
**4200-4201**. 4201 is `LanPort` in `NetworkConfig` — LAN discovery — so it never
needs a WAN forward. One port is correct.

### As deployed (2026-08-15)

Egg **34**, server **5** (`Bannerlord Coop`, uuid `9e2b8cf7-e32e-48ce-a5af-901ed2adaaa8`),
allocation **20** = `0.0.0.0:4200`, 8 GB RAM / 12 GB disk / unlimited CPU, owner
`jonathan`. The panel has no CLI for egg import or server creation, so both were
done through the app's own services (`EggImporterService::fromContent`,
`ServerCreationService::handle`) via `php artisan tinker` — the same code path the
admin UI uses, not hand-written DB rows.

Inside the volume:

- `DedicatedServer/` — the 5.7 GB install (6384 files), uploaded by hand.
  Carries a **`.nobackup`** marker, as does `.wine/`, so borgmatic's
  `exclude_if_present` skips both.
- `coop-data/` — `server-config.json`, `Game Saves/`, `logs/`. Deliberately
  **not** excluded: it is small and it is the only irreplaceable part.

Remaining manual bits: `sudo bash scripts/ufw-rules.sh` (or a one-off
`ufw allow 4200/udp`) and the router's WAN forward `4200/udp → 192.168.0.10:4200`.
Set a `password` in `coop-data/server-config.json` before the port is open.
Homepage tile + Kuma monitor only if it becomes a standing server — given the
~1.4-core idle cost it probably shouldn't.

### Asking upstream for a clean download

Filing this as a request is entirely normal — it is what every panel-hosted game
needs, and hosts already sell "Bannerlord Coop" servers. A *pull request* is not
the mechanism, but not because the project is closed: the mod's source is public
and takes contributions (see above). It is that the launcher we run isn't in that
repo, and the ask is for a *distribution channel*, which is a maintainer decision
rather than a patch. What to ask for, in
[`Bannerlord-Coop-Issues`](https://github.com/Bannerlord-Coop-Team/Bannerlord-Coop-Issues)
or Discord:

1. **A versioned server-only archive at a stable URL** (GitHub release asset is
   ideal: `.../releases/latest/download/BannerlordCoopServer-<ver>.zip`), so an
   install script can fetch and auto-update it without Steam credentials. This is
   how Minecraft, Factorio and every other proprietary-but-hostable server is
   done, and it costs them nothing in licensing.
2. **Console commands in `--no-tui` mode**, so a panel can stop the server
   cleanly instead of killing it, plus a configurable direct-connect UDP port on
   the server side. (Plain logging itself already exists — see above.)
3. **Publish the Linux build they already run.** Not "please write one" — issue
   #2843 shows a core dev running `DedicatedServer.Linux` natively in Docker,
   no Wine. If that ever ships alongside the Windows one, Wine, Xvfb and the
   `| cat` TTY workaround all disappear from this egg at once.

If they say yes to (1), the egg's install script collapses to a `curl` and it is
publishable to `pelican-eggs` as a normal community egg.

**Posted 2026-08-15** as
[BannerlordCoop#3044](https://github.com/Bannerlord-Coop-Team/BannerlordCoop/issues/3044)
(`funkekaiser`), still open, no replies yet. `upstream-request.md` holds the live
text of that issue — edit there, then `gh issue edit 3044 --body-file`.
