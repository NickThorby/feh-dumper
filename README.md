# feh-dumper

Dump Fire Emblem Heroes' game data yourself, without a rooted phone: run the game in
**[Waydroid](https://waydro.id/)** on a Linux box, let it download everything, then copy its app-private data
straight off the host. The dumps feed the `fire-emblem-legends-data` catalogue (a separate repo); decoding the
game's raw formats is not done here.

> **Status (2026-09-30):** Fire Emblem Heroes 10.9.0 runs in Waydroid, and a complete data dump (Japanese +
> English voices, plus US/EU/Japanese text) has been captured and hash-verified. True emulators don't work:
> see [Why emulators fail](#why-emulators-fail).

## Quick start

Tested on Debian 13 (kernel 6.12), Intel i7-8700K (UHD 630 iGPU), with a spare monitor and USB keyboard/mouse.
**[`RUNBOOK.md`](RUNBOOK.md) is the full fresh-box procedure** with every prerequisite and quirk. This is the
short version:

```sh
sudo setup/00-host-prereqs.sh     # binder devices, kernel modules, firewall for waydroid0, adb/pulseaudio
sudo setup/01-install-waydroid.sh # Waydroid (VANILLA) + weston + libhoudini (arm64 translation)
sudo setup/02-netdeps.sh          # iptables + dnsmasq (Debian's waydroid package omits them)
sudo setup/03-fix-net.sh          # waydroid-net.sh -> nftables backend (legacy iptables is broken on trixie)
bin/session --props               # boot headless; abilist must include arm64-v8a, product has no "sdk"
```

Then install GApps, register the device at <https://www.google.com/android/uncertified> (`bin/gsf-id`), and sign
in to Play. FEH hard-requires Play services. Then, **at the physical console**, run `bin/display`, install
FEH, play as a guest through the tutorial, and let it download. Copy the data from
`~/.local/share/waydroid/data/data/com.nintendo.zaba` on the host, or use `bin/dump` over adb.

## Scripts

| Script | Run as | What |
|---|---|---|
| `setup/00-host-prereqs.sh` | root | packages; binder devices (module + udev 0666); `loop`/`nft_masq` modules; UFW rules for `waydroid0`. Persists. |
| `setup/01-install-waydroid.sh` | root | repo.waydro.id apt repo + `waydroid`, `weston`; `waydroid init -s VANILLA`; libhoudini via [waydroid_script](https://github.com/casualsnek/waydroid_script) |
| `setup/02-netdeps.sh` | root | `iptables` + `dnsmasq-base` |
| `setup/03-fix-net.sh` | root | patches `waydroid-net.sh` to nftables (backs up the original); re-run after a `waydroid` upgrade |
| `bin/session [--props]` | user | (re)start a headless session and wait for boot. This is the fix when adbd freezes. |
| `bin/display` | user, **at the console** | weston on the DRM backend (hardware GL) + session + FEH: the stable way to play |
| `bin/gsf-id` | user | the id Google's uncertified-device form needs |
| `bin/probe` | user | where the game's data is and whether adb can read it (read-only) |
| `bin/dump` | user | APKs + game data → `dumps/<date>-v<version>/` + `manifest.json` (sha256 per file) |
| `bin/shell`, `bin/logcat` | user | adb shell (root); log filtered to the game, crashes and ARM translation |
| `bin/screen` | user | scrcpy-over-SSH-tunnel recipe for viewing from another computer |
| `bin/fetch-dump` | on the Mac | rsync `dumps/` from the box |

The adb scripts default to Waydroid's adbd at `192.168.240.112:5555` (check with `waydroid status`).
`DEVICE=<serial>` points them at anything else, e.g. a real phone over USB. Setup and session logs go to `logs/`.

## The dump (three languages)

A complete FEH 10.9.0 dump was captured this way (2026-09-30). It is **~11 GB**, laid out under
`data/com.nintendo.zaba/files/assets/`:

| Dir | Size | What |
|---|---|---|
| `Common` | 5.6 GB | shared, region-independent game assets (art, models, BGM, SFX) |
| `JPJA` | 2.5 GB | **Japanese** text + voices, extracted (full roster) |
| `ENCommon` | 2.3 GB | **English** voices: 33,695 `VOICE_*.ckb` |
| `USEN` / `EUEN` | 25 MB each | US / EU English text (`Message`) |

Plus the Nintendo-signed base APK. Voices exist for **both Japanese and English**. US and EU English differ
only in the `Message` text; their voices are the same `ENCommon` set.

**Three languages, one folder.** Switching the in-game language **deletes the other language's assets** from
the live install. So each language was captured as its own in-game state (US → JP → EU → US) and `rsync`'d
into one folder **without `--delete`** so they accumulate. Every state was hash-verified against the source.
`MASTER-sha256sums.txt` (127,228 files) is the combined integrity reference, with per-round manifests and
verify logs kept alongside. Re-verify anytime: `cd data && shasum -a 256 -c ../MASTER-sha256sums.txt`.

Method notes (also in the [runbook](RUNBOOK.md#quirks--troubleshooting-everything-that-bit-us)):

- A whole-tree `rsync` **stalls** on the ~85k-file scan over a USB drive. `rsync` just the new dir (e.g.
  `EUEN`), then **hash-verify the whole state** to catch anything missed.
- The obfuscated-name files (`SnZ77WFq`, `V9GiILGz`, `*~`) are FEH's mutable per-state asset catalog/index.
- **Keep the `sha256` manifests and re-verify.** On a flaky external drive this caught a silently corrupted
  `VOICE_*.ckb`, which was then re-copied.

### Ready to extract, but not here

The dump is **raw, packed game data**: `.ckb` voice/audio banks, `Message/*.bin.lz` (LZ-compressed) text, and
encrypted asset catalogs. Decoding and extracting it (unpacking the formats, mapping files to heroes and skills,
cataloguing) is **out of scope for this repo**, which only gets the bytes off the device. That work lives in
the sibling **`fire-emblem-legends-data`** catalogue.

## Why emulators fail

This project first tried ReDroid (Docker), then BlueStacks, MuMu and Android Studio's AVD. All of them crash the
same way. FEH runs ~10 s, then its GL thread takes `SIGSEGV` (null-pointer write, fault addr `0xa60`) at the
same instruction in `lib/arm64-v8a/libcocos2dcpp.so` (`pc 0x3d6d9a0`, the stub `mov w8,#0xa60; mov w9,#1;
strb w9,[x8]`), reached every frame from `org.cocos2dx.lib.Cocos2dxRenderer.onDrawFrame`. This was identical
across seven environments: ReDroid+libndk, ReDroid+libhoudini, BlueStacks, MuMu, and Android Studio's arm64
AVD on an M1 Pro under software SwiftShader, ANGLE, and the real M1 Pro GPU via Metal. So the cause is **not**
ARM translation (M1 runs arm64 natively), **not** the GPU (it crashes the same on real Metal), and **not** root
(the AVD is a stock unrooted `user` build). The common factor is that they are emulators. The game logs
`isEmulator=true` just before dying: its `Cocos2dxActivity.isAndroidEmulator()` checks `Build.PRODUCT`/`MODEL`
for `"sdk"`. Waydroid's LineageOS image reports `Build.PRODUCT=lineage_waydroid_x86_64`, with no `"sdk"`, so it
slips past.

The data lives only in app-private `/data/data/com.nintendo.zaba` (no `allowBackup`, no shared-storage copy;
on Android 10+ even `/sdcard/Android/data` is closed to adb). Getting it needs **root, or a container like
Waydroid where the host owns `/data`**.

## Notes

- adb (port 5555) gives full control. Keep it on the home LAN and never forward it on the router.
- Waydroid's adbd over TCP is flaky and only recovers with a full session restart (`bin/session`), not
  `waydroid container restart`. `sudo waydroid shell` (lxc-attach) and host-filesystem reads survive the hangs.
