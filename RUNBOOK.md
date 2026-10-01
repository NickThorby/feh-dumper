# Waydroid runbook — FEH from a fresh box to a dump

Everything needed to get Fire Emblem Heroes 10.9.0 running in Waydroid on a **new** Linux box and dump its
data. Waydroid works where true emulators don't (see [Why emulators fail](README.md#why-emulators-fail)):
its LineageOS image reports `Build.PRODUCT=lineage_waydroid_x86_64` — no `"sdk"` — so FEH's `isEmulator()`
self-destruct never fires.

This is the exact sequence we used (Debian 13, kernel 6.12, Intel i7-8700K / UHD 630). It is fiddly; each
prerequisite below is here because skipping it broke something. The `setup/` and `bin/` scripts automate the
mechanical parts; see [Scripts](README.md#scripts) for what each does. Run everything from the repo root.

> **Assumptions.** Linux x86_64; an Intel CPU (→ **libhoudini**; on AMD use `libndk` instead); a GPU with real
> DRM/GL (we used the Intel iGPU — needed for the stable `bin/display` step); a spare **monitor + USB
> keyboard/mouse** for the box; ~25 GB free.

---

## 0. Host prerequisites

```sh
sudo setup/00-host-prereqs.sh
```

This does three things, and each one persists across reboots:

**a. Binder devices.** Waydroid needs `/dev/binder`, `/dev/hwbinder` and `/dev/vndbinder`. Debian's kernel has
no binderfs, so the script creates them from the `binder_linux` module (`/etc/modprobe.d/waydroid-binder.conf`,
`/etc/modules-load.d/waydroid-binder.conf`) and a udev rule makes them `0666`, because Android's services open
them as non-root.

**b. Extra kernel modules.** `nft_masq` (and its NAT deps) fixes Android's NAT, and `loop` lets `system.img`
mount. They are listed in `/etc/modules-load.d/waydroid-feh.conf`.

**c. Host firewall.** It opens the `waydroid0` bridge. Without that the container gets no DHCP lease and no
internet, because UFW/Docker set the FORWARD policy to drop. With UFW active, the script adds persistent rules:

```sh
sudo ufw allow in on waydroid0                 # INPUT: DHCP/DNS from the container to the host
sudo ufw route allow in on waydroid0           # FORWARD: container -> internet
sudo ufw route allow out on waydroid0          # FORWARD: replies back to the container
```

Without UFW it prints these runtime rules instead. They **do not survive a reboot**, so re-run them before
each session:

```sh
sudo nft insert rule ip filter INPUT   iifname "waydroid0" accept
sudo nft insert rule ip filter FORWARD iifname "waydroid0" accept
sudo nft insert rule ip filter FORWARD oifname "waydroid0" accept
```

**PulseAudio** must also be running for your user, because the container bind-mounts the pulse socket and won't
start without it, even headless. The script installs it, and `bin/session` / `bin/display` start it when it isn't
running.

---

## 1. Install Waydroid + ARM translation

```sh
sudo setup/01-install-waydroid.sh
```

Adds the repo.waydro.id apt repo (falls back to the `bookworm` suite if `trixie` isn't published), installs
`waydroid` + `weston`, runs `waydroid init -s VANILLA`, starts `waydroid-container`, and installs **libhoudini**
via [waydroid_script](https://github.com/casualsnek/waydroid_script). Ends with `=== INSTALL DONE ===`.

## 2. Networking

```sh
sudo setup/02-netdeps.sh    # installs iptables + dnsmasq-base (Debian's waydroid pkg omits them)
sudo setup/03-fix-net.sh    # switch waydroid-net.sh to the nftables backend + two nft-syntax fixes
```

Why `03-fix-net.sh`: on trixie the legacy iptables backend has no working `mangle` table / `CHECKSUM` target, so
`waydroid-net.sh start` aborts. The script flips `LXC_USE_NFT="true"`, removes a stray leading `;` in the nft
ruleset (a Waydroid bug when IPv6 NAT is off), and feeds nft via `nft -f -` instead of one big argument. It
then brings the bridge up; you should see `waydroid0` with `inet 192.168.240.1` and an `lxc` nft table.

## 3. Boot a session and confirm it works

```sh
bin/session --props
```

It boots a headless session and prints the two things that make FEH run: `ro.product.cpu.abilist` must include
`arm64-v8a`, and `ro.product.name` must be `lineage_waydroid_x86_64` (no `"sdk"`).

## 4. Google Play (FEH requires Google Play services)

VANILLA has no GMS, so FEH shows *"won't run without Google Play services."* Install GApps and sign in:

```sh
sudo /opt/waydroid_script/venv/bin/python3 /opt/waydroid_script/main.py install gapps   # MindTheGapps on A13
bin/session
bin/gsf-id        # prints the GSF Android id (adb at 192.168.240.112:5555; DEVICE=... to override)
```

Register that id at <https://www.google.com/android/uncertified> with the Google account you'll use, **wait
~10 min**, then sign that account into Play. The Waydroid launcher renders black on a headless display, so
drive sign-in via `adb ... am start -a android.settings.ADD_ACCOUNT_SETTINGS` (or the Play Store activity),
not by tapping the home screen. A successful sign-in clears FEH's later `803-4204` "check your app-store
account" error and stabilises the home screen.

## 5. Run FEH — on a physical monitor

Headless software rendering **hangs repeatedly** (adbd freezes, the container wedges) once FEH reaches its
animated home screen. The reliable fix is hardware GL on a real screen:

1. Plug an **HDMI/DP monitor + USB keyboard & mouse** into the box (motherboard/Intel port).
2. Log in at the **physical console** (getty on tty1 → logind grants the seat + GPU/input access).
3. Run **at that console** (not over SSH — DRM needs the seat):

   ```sh
   bin/display
   ```

   It stops the headless weston and starts `weston --backend=drm-backend.so` on the Intel GPU, then the
   Waydroid session + FEH.
4. Install FEH from Play, **play as a guest** (don't link a Nintendo Account), finish the **tutorial** (the
   first battle + summon — required before the game will download its full asset set), and let it download.

## 6. Dump the data

The game's data is bind-mounted on the host — you can copy it directly (this survives the adbd/container
hangs), or use the repo's adb-based dumper:

```sh
# direct (host path, root):
sudo rsync -a ~/.local/share/waydroid/data/data/com.nintendo.zaba/  <dest>/
# or via adb, with a manifest:
bin/dump
```

For the multi-language dump and verification method, see [The dump](README.md#the-dump-three-languages) in
the top-level README.

---

## Surviving a reboot

**Persists automatically** (nothing to do): the FEH data on disk
(`~/.local/share/waydroid/data/data/com.nintendo.zaba`); the binder devices (udev/module config from §0a);
the extra kernel modules (`/etc/modules-load.d/waydroid-feh.conf`, §0b); the UFW rules for `waydroid0` (§0c); the `waydroid-net.sh` nftables patch
(a file edit, §2 — but a `waydroid` package update will revert it, so re-run `setup/03-fix-net.sh` after upgrades);
and the `waydroid-container` service (`systemctl enable`d).

**Does NOT persist — re-apply after each reboot before starting a session:**

1. **The weston compositor + Waydroid session.** These are not a boot service. Run `bin/display` at the
   console, or `bin/session` for a headless session; both also start PulseAudio. The container service starts on
   boot, but the *session* (the user side that renders and connects) is started by hand.
2. **Only without UFW:** the runtime `nft insert` firewall rules (§0c) are gone after boot. Re-run them first,
   or the container gets no DHCP/internet.

So a clean "after reboot, play/dump again" is just `bin/display` at the console.

---

## Quirks & troubleshooting (everything that bit us)

- **adbd over TCP freezes** (device shows `offline`, `waydroid shell`/scrcpy hang). Only a full
  `waydroid session stop && waydroid session start` (i.e. `bin/session`) restores it — a
  `waydroid container restart` does **not**. The container itself usually keeps running; `sudo waydroid shell`
  (lxc-attach) and host-filesystem reads keep working through the freeze, so prefer them for anything scripted.
- **`waydroid shell` needs root**, and eats flags: use `sudo waydroid shell -- <cmd -flags>` (the `--` passes
  `-p`, `-b`, etc. through to the Android command).
- **Whole-tree `rsync` stalls** on the ~85k-file scan over a USB drive. Rsync the *specific* changed directory
  (e.g. `files/assets/EUEN`), then **hash-verify the whole state** to catch anything missed.
- **Silent drive corruption** happens on flaky external drives — our per-round `shasum -c` caught a damaged
  `VOICE_*.ckb` that we re-copied. Always keep the manifests and re-verify.
- **Obfuscated-name files** (`SnZ77WFq`, `V9GiILGz`, `*~` in `files/assets/`) are FEH's mutable per-state asset
  catalog/index; they differ between language states — not corruption.
- **Networking must persist:** every container start re-runs `waydroid-net.sh`, so the `nft_masq`/`loop`
  modules and the `waydroid0` firewall rules must survive reboots or the session fails to boot again
  (`setup/00-host-prereqs.sh` persists both when UFW is active).
- **Interactive viewing:** scrcpy over an SSH tunnel to Waydroid's adb
  (`bin/screen` prints the recipe) works but rides on the flaky adbd —
  use the physical display for anything interactive (menus, sign-in, language switching).
