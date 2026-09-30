# feh-dumper

> **Status (2026-09-30): Fire Emblem Heroes 10.9.0 runs in [Waydroid](https://waydro.id/), and a
> complete data dump — Japanese + English voices, and US/EU/Japanese text — has been captured and
> hash-verified.** It does **not** run in true emulators (ReDroid, BlueStacks, MuMu, Android Studio's
> AVD): they all crash identically ~10 s in with a `SIGSEGV` in the game's own `libcocos2dcpp.so`
> (every frame from `Cocos2dxRenderer.onDrawFrame`), because the game checks `Build.PRODUCT` for
> `"sdk"` and deliberately self-destructs — see [Why emulators fail](#why-emulators-fail). **Waydroid**
> boots a LineageOS image whose `Build.PRODUCT` is `lineage_waydroid_x86_64` (no `"sdk"`), so the check
> passes and the game runs (arm64 via libhoudini). See the **[Waydroid route](#waydroid-route)**.

Dump Fire Emblem Heroes' game data yourself. Two on-box Android options are here — **Waydroid** (an LXC
container; the game runs in it) and **[ReDroid](https://github.com/remote-android/redroid-doc)** (Docker;
gets you an Android, but the game self-destructs in it). Either way, the `bin/*` scripts copy the game's
APKs and downloaded data off it, over adb, with a checksum manifest. The dumps feed the
`fire-emblem-legends-data` catalogue (a separate repo); decoding the game's raw formats is not done here.

`bin/*` also work against a real device over USB/adb (`DEVICE=<serial> bin/probe` / `bin/dump`).

## Waydroid route

Runs FEH on a Linux box with an x86 GPU. Tested on Debian 13 (kernel 6.12), Intel i7-8700K (UHD 630 iGPU).
The scripts referenced here are in [`waydroid/`](waydroid/) — see [`waydroid/README.md`](waydroid/README.md)
for the exact commands and the gotchas each one fixes.

1. **Install + ARM translation:** `sudo bash waydroid/01-install-waydroid.sh` — Waydroid from repo.waydro.id,
   `waydroid init` (VANILLA), and **libhoudini** (Intel's arm64 translation) via
   [waydroid_script](https://github.com/casualsnek/waydroid_script). Also installs `weston` (headless box).
2. **Networking:** `sudo bash waydroid/03-netdeps.sh` (Debian's `waydroid` pkg omits `iptables`/`dnsmasq`)
   then `sudo bash waydroid/04-fix-net.sh` (makes `waydroid-net.sh` use the **nftables** backend — the
   legacy iptables `mangle`/`CHECKSUM` path is broken on trixie). Also needs modules `nft_masq` + `loop`
   (persisted to `/etc/modules-load.d/`), and the host firewall opened for the `waydroid0` bridge
   (`nft insert rule ip filter INPUT/FORWARD iifname/oifname "waydroid0" accept` — UFW/Docker default-drop).
3. **GApps + sign-in:** FEH hard-requires Google Play services. Install GApps
   (`waydroid_script install gapps`), get the GSF id (`bin/gsf-id` against the Waydroid adb), register it at
   <https://www.google.com/android/uncertified>, wait, then sign a Google account into Play. This clears
   FEH's `803-4204` app-store error and stabilises the home screen.
4. **Run it — on a physical monitor.** Headless software rendering hangs repeatedly (adbd freezes, the
   container wedges). Plug an HDMI/DP monitor + USB keyboard/mouse into the box, log in at the console, and
   `bash waydroid/physical-display.sh` — this runs weston on the **DRM backend (Intel GPU, hardware GL)**,
   which is stable. Install FEH from Play (or `adb install`), play as a **guest**, finish the tutorial, and
   let it download.
5. **Dump:** `DEVICE=<waydroid-adb> bin/dump`, or copy straight from the host — the game's data is bind-mounted
   at `~/.local/share/waydroid/data/data/com.nintendo.zaba` (no adb needed).

### Multiple languages

Switching the in-game language **deletes the other language's assets** from the live install (JP voices live
in `files/assets/JPJA`, EN voices in `ENCommon`, per-locale text in `USEN`/`EUEN`/…; `Common` is shared).
To collect them all: capture one language state, switch language in-game, let it download, capture again —
`rsync` each into one folder **without `--delete`** so they accumulate. Notes:

- A whole-tree `rsync` **stalls** on the ~85k-file scan over a USB drive; `rsync` just the new dir (e.g.
  `EUEN`) then **hash-verify the whole state** to catch anything missed.
- The obfuscated-name files (`SnZ77WFq`, `V9GiILGz`, `*~`) are FEH's mutable per-state asset catalog/index.
- **Always keep the per-round `sha256` manifests and re-verify** — on a flaky external drive this caught a
  silently-corrupted `VOICE_*.ckb` that was then re-copied.

## Why emulators fail

FEH runs ~10 s, then its GL thread takes `SIGSEGV` (null-pointer write, fault addr `0xa60`) at the same
instruction in `lib/arm64-v8a/libcocos2dcpp.so` (`pc 0x3d6d9a0`, the stub `mov w8,#0xa60; mov w9,#1;
strb w9,[x8]`), reached every frame from `org.cocos2dx.lib.Cocos2dxRenderer.onDrawFrame`. Identical across
seven environments: ReDroid+libndk, ReDroid+libhoudini, BlueStacks, MuMu, and Android Studio's arm64 AVD
on an M1 Pro under software SwiftShader, ANGLE, and the real M1 Pro GPU via Metal. So it is **not** ARM
translation (M1 runs arm64 natively), **not** the GPU (crashes the same on real Metal), and **not** root
(the AVD is a stock unrooted `user` build). The common factor is that they are emulators: the game logs
`isEmulator=true` (its `Cocos2dxActivity.isAndroidEmulator()` checks `Build.PRODUCT`/`MODEL` for `"sdk"`)
just before dying. Waydroid's LineageOS fingerprint has no `"sdk"`, so it slips past.

The data lives only in app-private `/data/data/com.nintendo.zaba` (no `allowBackup`, no shared-storage copy;
on Android 10+ even `/sdcard/Android/data` is closed to adb), so it needs **root, or a rooted container like
Waydroid where the host owns `/data`**.

## ReDroid route (Android boots; the game won't run in it)

Kept because it sets up an Android with Play + ARM translation quickly. FEH self-destructs in it (above),
so it is not a route to the data on its own, but the `bin/*` scripts and `host/setup.sh` come from here.

```sh
sudo host/setup.sh           # packages, binder module (persisted), checks
image/build.sh               # ReDroid 11 + OpenGapps + libndk -> feh-android:… (~10 min, ~1 GB)
bin/up                       # start the container, wait for boot, print the ABIs (must include arm64-v8a)
bin/screen                   # scrcpy command to run on the Mac
```

Other images if you want to experiment: `TRANSLATION=houdini image/build.sh`,
`ANDROID=12.0.0 GAPPS=mindthegapps image/build.sh` (a different Android version needs a fresh `state/`).

## Scripts

| Script | What |
|---|---|
| `waydroid/*.sh` | the Waydroid route (install, networking fixes, session, physical display) — see `waydroid/README.md` |
| `host/setup.sh` | `sudo`; packages, binder module + its boot config; idempotent (ReDroid) |
| `image/build.sh` | builds the ReDroid image via pinned [redroid-script](https://github.com/ayasa520/redroid-script) |
| `bin/up`, `bin/down` | start/stop the `feh-android` (ReDroid) container |
| `bin/screen` | scrcpy command for viewing/controlling the screen remotely |
| `bin/shell`, `bin/logcat` | adb shell (root); filtered log |
| `bin/gsf-id` | the id Google's uncertified-device form needs |
| `bin/probe` | where the game's data is on a device and whether adb can read it (read-only) |
| `bin/dump` | APKs + game data → `dumps/<date>-v<version>/` + `manifest.json` |
| `bin/fetch-dump` | run on the Mac: copy dumps from the box |

`DEVICE=<adb serial>` points the adb scripts at another device (default: `localhost:5555`). For Waydroid,
connect adb to its container IP (`adb connect 192.168.240.112:5555`) or tunnel it.

## Notes

- adb (port 5555) gives full control: keep it on the home LAN, never forward it on the router.
- No ashmem / no binderfs in current Debian kernels: ReDroid boots with `androidboot.use_memfd=true`;
  Waydroid uses the pre-created `/dev/binder,hwbinder,vndbinder` nodes.
- Waydroid's adbd over TCP is flaky and only recovers with a full `waydroid session stop/start` (not
  `container restart`); `sudo waydroid shell` (lxc-attach) + host-filesystem reads survive the hangs.
