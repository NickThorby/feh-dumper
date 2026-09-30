# feh-dumper

> **Status (2026-09-30): Fire Emblem Heroes 10.9.0 does not run in ReDroid.** It starts, signs in to
> Google Play Games, then crashes itself ~10 s later in its graphics thread, at the same place under
> both ARM translators (libndk and libhoudini) — a deliberate crash in the game's code, not a
> translation bug. BlueStacks and MuMu on macOS end the same way. A real device is needed: an
> unrooted phone can't reach the game's data (it lives only in the app's private
> `/data/user/0/com.nintendo.zaba`; no shared-storage copy, no `allowBackup`), so a dedicated rootable
> spare phone is the remaining route — `DEVICE=<serial> bin/dump` supports that. The scripts below work
> up to the point of launching the game.

Dump Fire Emblem Heroes' game data yourself: Android in Docker ([ReDroid](https://github.com/remote-android/redroid-doc))
on a Linux box, with Google Play and ARM translation, and scripts that copy the game's APKs and
downloaded data off it with a manifest. The dumps feed the `fire-emblem-legends-data` catalogue (a
separate repo); decoding the game's raw formats is not done here yet.

Also works against a phone over USB (no root needed): `DEVICE=<serial> bin/probe` / `bin/dump`
copy whatever adb can read.

## Requirements

- Linux x86_64 with the kernel's binder driver (Debian 12/13: `binder_linux` module, set up by
  `host/setup.sh`), Docker with the compose plugin, ~20 GB free.
- Tested on Debian 13 (kernel 6.12), i7-8700K. Any GPU: Android renders in software (SwiftShader).
- On the computer you look at the screen from: `brew install scrcpy android-platform-tools`.

## Fresh box → dump

```sh
git clone https://github.com/NickThorby/feh-dumper.git ~/feh-dumper && cd ~/feh-dumper
sudo host/setup.sh           # packages, binder module (persisted), checks
image/build.sh               # ReDroid 11 + OpenGapps + libndk -> feh-android:… (~10 min, downloads ~1 GB)
bin/up                       # starts the container, waits for boot, prints the ABIs (must include arm64-v8a)
bin/screen                   # prints the scrcpy command to run on the Mac
```

Then, once per fresh `state/` (manual):

1. Open the Play Store once, then `bin/gsf-id` and register that id at
   <https://www.google.com/android/uncertified> with the Google account you'll use. Wait a few minutes,
   `bin/down && bin/up`, sign in to Play.
2. Install Fire Emblem Heroes from Play and start it. **Play as a guest** (don't link your
   Nintendo Account). Accept the terms and let it download all its data; it's slow in software rendering.
3. `bin/dump` → `dumps/<date>-v<version>/` with `apk/`, `device/…` and `manifest.json`.
4. On the Mac: `bin/fetch-dump` (rsyncs `~/feh-dumper/dumps/` from the box).

Game updates: update it in Play, start it so it downloads, `bin/dump` again. `state/` keeps the Google
sign-in, the game and its data between restarts and image rebuilds; delete it to start over.

## If the game won't run

`bin/logcat` shows the game's log, crashes and ARM-translation messages. Try other images:

```sh
TRANSLATION=houdini image/build.sh                  # Intel's libhoudini instead of libndk
ANDROID=12.0.0 GAPPS=mindthegapps image/build.sh    # Android 12 (OpenGapps is 11-only)
bin/down && bin/up                                  # compose uses the newest build (.env)
```

A different Android version needs a fresh `state/` (move it aside).

## Scripts

| Script | What |
|---|---|
| `host/setup.sh` | `sudo`; packages, binder module + its boot config; idempotent |
| `image/build.sh` | builds the Android image with the pinned [redroid-script](https://github.com/ayasa520/redroid-script) (`ANDROID`, `GAPPS`, `TRANSLATION`) |
| `bin/up`, `bin/down` | start/stop the `feh-android` container |
| `bin/screen` | scrcpy command for viewing/controlling the screen remotely |
| `bin/shell`, `bin/logcat` | adb shell (root); filtered log |
| `bin/gsf-id` | the id Google's uncertified-device form needs |
| `bin/probe` | where the game's data is on a device and whether adb can read it (read-only) |
| `bin/dump` | APKs + game data → `dumps/<date>-v<version>/` + `manifest.json` |
| `bin/fetch-dump` | run on the Mac: copy dumps from the box |

`DEVICE=<adb serial>` points the adb scripts at another device (default: the container, `localhost:5555`).

## Notes

- adb (port 5555) gives full control of the container: keep it on the home LAN (`ADB_BIND=<box ip>` in
  `.env` to limit it to one interface), never forward it on the router.
- No ashmem in current kernels: the container boots with `androidboot.use_memfd=true`.
- libhoudini/libndk support per Android version follows redroid-script: libndk on 11/12, OpenGapps on 11.
