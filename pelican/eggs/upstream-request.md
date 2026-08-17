# Feature request to the Bannerlord Coop team

**Posted 2026-08-15** as
[BannerlordCoop#3044](https://github.com/Bannerlord-Coop-Team/BannerlordCoop/issues/3044)
by `funkekaiser`. Open, no replies yet.

**This file mirrors the live issue and the live issue is authoritative.** Jonathan
edits the body on GitHub directly. Before touching it here, pull the live copy
(`gh issue view 3044 --repo Bannerlord-Coop-Team/BannerlordCoop --json body`) and
never push a body without him saying so in that exact turn: a `--body-file` push
replaces the whole body, and on 2026-08-15 one did exactly that to his edit.
(Recovery, if it happens again: the GraphQL `userContentEdits` node's `diff`
field holds the *full body* at each revision, so nothing is actually lost.)

Body below is the live text as of 2026-08-15 11:40Z, verbatim. Rev 2 rewrote
asks 1 and 3 after reading the upstream repo properly (a native Linux server
exists, #2843; the client is not pinned to port 4200). Rev 3 folded in the Nexus
finding: they already publish the server package there, so ask 2 shrank to "put
it behind a stable URL", and ask 3 became "keep reading stdin with --no-tui"
since the flag itself already exists.

---

**Title:** [DEDICATED SERVER] on a hosting panel: ship the Linux build, a stable download URL, and keep stdin commands with --no-tui

**Body:**

Thanks for shipping a real dedicated server with the mod!

I've got it running on my own hardware, managed through a [Pelican](https://pelican.dev) panel (the Pterodactyl successor). It works well, and the three things below would make it work *cleanly* for anyone doing the same.

**First, the results, since they may be useful to you:** the server runs headless under **Wine 11 on Debian 12**, in a container, with no Bannerlord installed and no Steam client:

- Cold boot to `SERVING` in **52 s**, building a fresh world from `default_new_game.sav` — actually faster than the same build on the Windows PC the files came from (76 s).
- UDP 4200 listening, autosave writing the world in ~1.6 s, `stop` exiting 0.
- With no Steam client present it fell back to direct-connect exactly as `release-info.txt` promises, no configuration needed.
- The `Cannot load: 0Harmony.dll / Common.dll / SandBox.dll / GameInterface.dll / Steamworks.NET.dll` lines appear identically on Windows, so they're clearly benign, but they do send people hunting for a problem that isn't there.

### 1. Ship the Linux build alongside the Windows one

#2843 has an environment block reading "Native Linux dedicated server, no Wine · .NET runtime 6.0.36, x64 · Dedicated-server repository commit `677f335`", with Docker restarting the process under a restart policy, and `ModuleValidatorTests` covers a `DedicatedServer.Linux` module ID alongside the Windows one. Meanwhile the Workshop item ships Windows only — `release-info.txt` is headed "Bannerlord Coop Dedicated Server (Windows x64)" and `engine/Modules/` contains `DedicatedServer.Windows`.

**The ask:** publish the Linux build too, even as an explicitly unsupported or experimental artifact with a "known-issues, don't file crashes against this" note on it.

Right now linux hosting means Wine plus Xvfb plus a TTY workaround (ask 3), all of which sit between you and a clean bug report when something goes wrong. A native build removes that whole layer. I'm happy to be a guinea pig: I have the panel, a spare campaign to break, and no expectation of support.

### 2. A stable URL for the server package you already publish

I wrote this section thinking the server only existed inside the Workshop item. It doesn't: the Nexus page has it as an optional file (`DedicatedServer`, 0.1.2-2, 4.1 GB, 14 Aug), version-labelled to match the client file. That is already most of what I was asking for, so thank you, and the remaining ask is much smaller than what I first wrote.

What is left is that no install script can reach it. Panels install a game server by fetching an archive from a URL, unpacking, and running it. Nexus downloads need an authenticated session: `download_link.json` returns a URL only for premium accounts, free accounts have to click the slow-download page for a short-lived token, and this mod sets `directDownloadEnabled: false`, so the Vortex/nxm path is closed too. The Workshop is no better, since Workshop items for a paid game can't be fetched anonymously:

```
$ steamcmd +login anonymous +workshop_download_item 261550 3770450698 +quit
Downloading item 3770450698 ...
ERROR! Download item 3770450698 failed (Failure).
```

So today a host either puts real Steam or Nexus credentials into a hosting panel, or downloads 4-6 GB by hand and re-uploads it on every update, with no signal that an update happened.

**The ask:** mirror that same archive at a stable unauthenticated URL. A GitHub release asset is ideal:

```
https://github.com/.../releases/latest/download/BannerlordCoopServer-<version>.zip
```

It is the same file you already hand out on Nexus, from your own URL, so no licensing change and no third party redistribution. It would let an install script pin a version and auto-update, which is what actually removes the host/client mismatch your docs warn about, and it is the difference between a Pelican/Pterodactyl "egg" that can be published for everyone and one that can't, since a public recipe can't ask people to paste credentials.

Asks 1 and 2 compose: a Linux build behind a stable URL turns hosting this on any panel into a `curl` and an unzip.

### 3. Keep reading console commands when the TUI is off

Withdrawing the first half of this ask: `--no-tui` already exists. It is in `BannerlordCoopServer.exe --help` ("plain console output (no log/players/command panes); automatic when stdout or stdin is redirected"), and that auto-detection is why piping the output through `cat` worked. My fault for not running `--help` before assuming. In that mode the console is clean and the `@DS@` events reach stdout, which is everything a panel needs to see the server come up.

The real problem is that "no command panes" also means no command input. In plain mode the server never reads stdin, so there is no way to stop it:

- The panel sends `stop` on stdin, nothing happens, and it eventually SIGKILLs the process.
- Typed by hand on a real pty, where the input echoes back so it is definitely arriving, neither `stop` nor `help` gets a response.
- `kill -INT` is ignored. The banner says "Press Ctrl+C to stop", but that is a Windows console event and Wine does not synthesise it from a Unix signal.

So the two modes are exclusive. The TUI has commands, but its output is unusable for a panel and swallows the `@DS@` events. `--no-tui` has usable output and no commands. Every automated host has to pick the second and then kill the process, which given #2593 is how saves get corrupted.

**The ask:** in `--no-tui` mode, keep the line reader running and accept the same commands, `stop` above all. A `SIGTERM` handler that saves and exits would do just as well and would need no client changes.

Separately, a server-side port setting would still help. `-p/--port` is documented as "port the ENGINE is started as a custom server on (default: 7210), NOT the port players connect to", and clients join on UDP 4200 with nothing in `server-config.json` to move it. Correcting myself from the first version of this issue: the client half is already solved, since the connect dialog has a Port field ("Leave 4200 unless the host changed it"). It is only the server that is pinned, and `NetworkConfig.Port` is already a settable property, so this may be a matter of the launcher reading one more key. It would let more than one server run per host and let the allocation sit in the port range panels manage by default.

### Small doc notes

`deploy/Server Instructions.md` tells hosts to forward UDP **4200-4201**. As far as I can tell 4201 is `NetworkConfig.LanPort` (LAN discovery) and never needs a WAN forward, might be worth trimming so people don't open a port they don't need.

The flag list is only visible by running `--help`. `release-info.txt` documents `--data-dir` and nothing else, so `--no-tui`, `--no-watchdog` and the `devModuleRoot` config key are effectively undiscoverable. A "run --help for the full list" line in the release notes would cover it.

Happy to write up the full Wine setup as a compatibility note for your docs or Discord if that's useful to other self-hosters.

---

## If they ask for detail

- Image: `ghcr.io/parkervcp/yolks:wine_latest` (Debian 12, Wine 11.0), container
  user non-root, no GPU.
- `xvfb-run` hangs the launcher (Xvfb starts, Wine never launches); starting Xvfb
  explicitly and exporting `DISPLAY=:0` works.
- `--data-dir "Z:\home\container\coop-data"` works and is what keeps saves out of
  the Wine prefix.
- Idle cost ~1.4 cores / 1.25 GB RSS with zero players — expected for a ticking
  campaign, but worth documenting for people sizing a box.
