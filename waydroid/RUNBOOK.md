# Waydroid runbook — FEH from a fresh box to a dump

Everything needed to get Fire Emblem Heroes 10.9.0 running in Waydroid on a **new** Linux box and dump its
data. Waydroid works where true emulators don't (see [Why emulators fail](../README.md#why-emulators-fail)):
its LineageOS image reports `Build.PRODUCT=lineage_waydroid_x86_64` — no `"sdk"` — so FEH's `isEmulator()`
self-destruct never fires.

This is the exact sequence we used (Debian 13, kernel 6.12, Intel i7-8700K / UHD 630). It is fiddly; each
prerequisite below is here because skipping it broke something. The `*.sh` scripts in this folder automate the
mechanical parts — read [`README.md`](README.md) for what each does.

> **Assumptions.** Linux x86_64; an Intel CPU (→ **libhoudini**; on AMD use `libndk` instead); a GPU with real
> DRM/GL (we used the Intel iGPU — needed for the stable physical-display step); a spare **monitor + USB
> keyboard/mouse** for the box; ~25 GB free. The scripts hardcode user `nick` and `/home/nick/...` paths and
> the Intel GPU — adjust them for your box/user.

---

## 0. Prerequisites the scripts do NOT set up — do these first

**a. Binder devices.** Waydroid needs `/dev/binder`, `/dev/hwbinder`, `/dev/vndbinder`. Debian's kernel has
no binderfs, so create them from the `binder_linux` module. (On our box the ReDroid `host/setup.sh` had
already done this.) On a bare box:

```sh
echo 'options binder_linux devices=binder,hwbinder,vndbinder' | sudo tee /etc/modprobe.d/waydroid.conf
echo binder_linux | sudo tee /etc/modules-load.d/binder.conf
sudo modprobe -r binder_linux 2>/dev/null; sudo modprobe binder_linux
# make them world-usable (Android's services open them):
printf 'KERNEL=="binder", MODE="0666"\nKERNEL=="hwbinder", MODE="0666"\nKERNEL=="vndbinder", MODE="0666"\n' \
  | sudo tee /etc/udev/rules.d/99-binder.rules
sudo udevadm control --reload && sudo udevadm trigger
ls -l /dev/binder /dev/hwbinder /dev/vndbinder   # all three must exist
```

**b. Extra kernel modules** (loading `nft_masq` fixes Android NAT, `loop` lets `system.img` mount):

```sh
printf 'loop\nnf_nat\nnft_nat\nnft_masq\nnft_chain_nat\n' | sudo tee /etc/modules-load.d/waydroid-feh.conf
sudo modprobe loop nf_nat nft_nat nft_masq nft_chain_nat
```

**c. Host firewall** — open the `waydroid0` bridge, or the container gets no DHCP lease and no internet
(UFW/Docker set the FORWARD policy to drop). These are runtime rules; persist them via your firewall config:

```sh
sudo nft insert rule ip filter INPUT   iifname "waydroid0" accept
sudo nft insert rule ip filter FORWARD iifname "waydroid0" accept
sudo nft insert rule ip filter FORWARD oifname "waydroid0" accept
```

**d. PulseAudio** running for the user — the container bind-mounts the pulse socket and won't start without it,
even headless:

```sh
export XDG_RUNTIME_DIR=/run/user/$(id -u)
pulseaudio --start --exit-idle-time=-1
ls -l "$XDG_RUNTIME_DIR/pulse/native"   # socket must exist
```

---

## 1. Install Waydroid + ARM translation

```sh
sudo bash 01-install-waydroid.sh
```

Adds the repo.waydro.id apt repo (falls back to the `bookworm` suite if `trixie` isn't published), installs
`waydroid` + `weston`, runs `waydroid init -s VANILLA`, starts `waydroid-container`, and installs **libhoudini**
via [waydroid_script](https://github.com/casualsnek/waydroid_script). Ends with `=== INSTALL DONE ===`.

## 2. Networking

```sh
sudo bash 03-netdeps.sh     # installs iptables + dnsmasq-base (Debian's waydroid pkg omits them)
sudo bash 04-fix-net.sh     # switch waydroid-net.sh to the nftables backend + two nft-syntax fixes
```

Why `04`: on trixie the legacy iptables backend has no working `mangle` table / `CHECKSUM` target, so
`waydroid-net.sh start` aborts. The script flips `LXC_USE_NFT="true"`, removes a stray leading `;` in the nft
ruleset (a Waydroid bug when IPv6 NAT is off), and feeds nft via `nft -f -` instead of one big argument. It
then brings the bridge up; you should see `waydroid0` with `inet 192.168.240.1` and an `lxc` nft table.

## 3. Boot a session and confirm it works

```sh
sudo bash restart-session.sh   # or, for the headless smoke-test with prop output: bash 02-session.sh
```

Confirm arm64 translation and the non-emulator fingerprint (the two things that make FEH run):

```sh
sudo waydroid shell -- getprop ro.product.cpu.abilist   # must include arm64-v8a
sudo waydroid shell -- getprop ro.product.name          # lineage_waydroid_x86_64  (no "sdk")
```

## 4. Google Play (FEH requires Google Play services)

VANILLA has no GMS, so FEH shows *"won't run without Google Play services."* Install GApps and sign in:

```sh
sudo /opt/waydroid_script/venv/bin/python3 /opt/waydroid_script/main.py install gapps   # MindTheGapps on A13
sudo bash restart-session.sh
DEVICE=192.168.240.112:5555 bin/gsf-id        # prints the GSF Android id (adb-connect first if needed)
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
   bash physical-display.sh
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
DEVICE=192.168.240.112:5555 bin/dump
```

For the multi-language dump and verification method, see [The dump](../README.md#the-dump-three-languages) in
the top-level README.

---

## Quirks & troubleshooting (everything that bit us)

- **adbd over TCP freezes** (device shows `offline`, `waydroid shell`/scrcpy hang). Only a full
  `waydroid session stop && waydroid session start` (i.e. `restart-session.sh`) restores it — a
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
  modules and the `waydroid0` firewall rules must survive reboots or the session fails to boot again.
- **Interactive viewing:** scrcpy over an SSH tunnel to Waydroid's adb
  (`ssh -L 5999:192.168.240.112:5555 …` then `scrcpy -s localhost:5999`) works but rides on the flaky adbd —
  use the physical display for anything interactive (menus, sign-in, language switching).
