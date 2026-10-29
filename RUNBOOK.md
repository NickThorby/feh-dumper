# Waydroid runbook — FEH from a fresh box to a dump

Everything needed to get Fire Emblem Heroes running in Waydroid on a **new** Linux box and dump its data
(done for 10.9.0 and 10.10.0), and to re-dump it when a new release comes out (§7). Waydroid works where true emulators don't (see [Why emulators fail](README.md#why-emulators-fail)):
its LineageOS image reports `Build.PRODUCT=lineage_waydroid_x86_64` — no `"sdk"` — so FEH's `isEmulator()`
self-destruct never fires.

This is the exact sequence we used (Debian 13, kernel 6.12, Intel i7-8700K; a GTX 980 Ti on nouveau, replaced on
2026-10-29 by an Intel Arc A380 on i915, see [Changing the GPU](#changing-the-gpu)). It is fiddly; each
prerequisite below is here because skipping it broke something. The `setup/` and `bin/` scripts automate the
mechanical parts; see [Scripts](README.md#scripts) for what each does. Run everything from the repo root.

> **Assumptions.**
> - Linux x86_64 with an Intel CPU (→ **libhoudini**; on AMD use `libndk` instead).
> - A GPU with a **Mesa** driver (real DRM/GL), needed for the stable `bin/display` step. Waydroid can't render on
>   NVIDIA's proprietary driver.
>   - On this box that's an Intel Arc A380 on **i915** since 2026-10-29. Before that it was a GTX 980 Ti on
>     **nouveau**.
>   - The i7-8700K's iGPU is unusable: the motherboard has no outputs for it and no firmware setting to enable it.
> - A spare **monitor and mouse** for the box. A keyboard is only needed for the first setup.
> - About 25 GB free.

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

**If Docker runs on the box with a locked-down `DOCKER-USER` chain** (one that ends in a DROP, as the media
server's does), that chain also sees Waydroid's forwarded traffic. Docker jumps to it from the top of `FORWARD`,
so the UFW rules above never get a say. It needs `-A DOCKER-USER -i waydroid0 -s 192.168.240.0/24 -j RETURN`
above its DROP. Here that rule lives in thorby-media's `setup.sh` (its decision D41).
- **The symptom when it's missing** is FEH's "connection error": inside Android, the gateway and DNS still answer,
  but nothing past the box does.
- **Check it** with `sudo iptables -L DOCKER-USER -n` after reboots and Docker upgrades.

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

On the GTX 980 Ti (nouveau), headless rendering **hung repeatedly** (adbd froze, the container wedged) once FEH
reached its animated home screen.
- **On the Arc A380 (i915),** headless FEH reached and rendered that home screen without hanging.
- **But Waydroid's auto-suspend** (`suspend_action = freeze`) froze the idle container after about a minute, so
  long headless runs are still untested.
- **Monitor mode stays the documented way to play**, since you interact with the screen anyway:

1. Plug an **HDMI/DP monitor and a USB mouse** into the box. The monitor goes on the GPU's own ports.
2. Once, install the display service: `sudo setup/04-feh-display.sh`. It installs `feh-display.service`, which
   runs `weston --backend=drm-backend.so` (kiosk shell) as you on **tty9**.
   - **Which GPU:** the one Waydroid renders on. `setup/feh-display/feh-gpu` picks it at run time by Waydroid's own
     rule (see Quirks).
   - **Access:** its PAM session gives weston the seat, i.e. the GPU and input devices. No console login is needed.
   - **Log:** weston writes to `/run/user/$UID/weston-feh.log`, including its `GL renderer:` line.
3. Then, **over SSH**:

   ```sh
   bin/display          # stop headless, start feh-display, boot the session, check the GPU, launch FEH
   bin/display --stop   # stop it, back to the headless session
   ```

   `bin/display` refuses if no monitor is connected to the GPU. It also stops if Android disagrees about the GPU:
   gralloc isn't on its render node, or `ro.hardware.vulkan` doesn't match its driver. That check is in
   `bin/_gpu.sh`, and `bin/session` runs it too.
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

## 7. A new FEH release: update and re-dump

This is the routine used for 10.10.0 (2026-10-06) and its data-only update (2026-10-16), run entirely over SSH
from the Mac with the drive attached there. Each release gets its own **new** dump folder,
`feh-<version>-<date>/`, because existing dumps are read-only. A **data-only update** (new in-game download,
same APK) keeps the real APK version and gets a new date, e.g. `feh-10.10.0-2026-10-16`. Don't invent a
version number; say in `INFO.txt` that it's a data update.

**a. Screen up.** Plug in the monitor and mouse, then run `bin/display` over SSH (§5).

**b. Update the APK (if there's a new one).** Waydroid's Play Store may not offer the update (it didn't for
10.10.0). If not, download the **arm64-v8a** APK (the installed build is arm64; check `primaryCpuAbi` in
`dumpsys package com.nintendo.zaba`) and install it as an in-place update, which keeps the game data:

```sh
# on the Mac: the signing cert must match the installed one, or Android refuses the update
unzip -p new.apk META-INF/NINTENDO.RSA | openssl pkcs7 -inform DER -print_certs | openssl x509 -noout -fingerprint -sha256
#   Nintendo's: 1B:C2:C2:5D:00:8B:FD:03:02:3C:1B:A6:01:40:DF:D2:C1:7F:85:0A:4A:D5:25:03:88:E2:CF:29:2E:02:16:7D
# on the box: install via pm inside the container (no adbd involved)
sudo cp new.apk ~/.local/share/waydroid/data/local/tmp/feh.apk
sudo waydroid shell -- pm install -r /data/local/tmp/feh.apk && sudo rm ~/.local/share/waydroid/data/local/tmp/feh.apk
```

Then launch FEH (`sudo waydroid shell -- am start -n com.nintendo.zaba/org.cocos2dx.cpp.AppActivity`) and let
it download in its current language.

**c. Capture each language state.** **Start with the language the box was left in** (the last state of the
previous dump), so the update's first download is just the delta. Check which one it is from the live data:

```sh
sudo bash -c 'du -sh ~nick/.local/share/waydroid/data/data/com.nintendo.zaba/files/assets/{JPJA,ENCommon,USEN,EUEN}'
#   JP: JPJA ~2.6G, no ENCommon      US: ENCommon ~2.4G + USEN 26M      EU: ENCommon ~2.4G + EUEN 26M
```

Every switch between Japanese and English downloads that language's voices again (~2.6 GB JPJA or ~2.4 GB
ENCommon). US ↔ EU is only ~26 MB of text. So keep the two English states next to each other: from JP go
**JP → EU → US** (2026-10-16), and from US go **US → EU → JP** (2026-10-06). For each state, after its
download finishes:

```sh
LIVE=~/.local/share/waydroid/data/data/com.nintendo.zaba
STAGE=~/feh-dumper/dumps/feh-<version>-<date>            # staging on the box's internal disk
sudo waydroid shell -- am force-stop com.nintendo.zaba; sleep 2   # no half-written files
sudo waydroid shell -- pidof com.nintendo.zaba           # must print nothing; if it does, force-stop again (Quirks)
mkdir -p $STAGE/data/com.nintendo.zaba $STAGE/apk $STAGE/state-index/$S
sudo rsync -a --out-format=%n $LIVE/ $STAGE/data/com.nintendo.zaba/ > $STAGE/changes-$S.list   # NO --delete
sudo find $LIVE/files/assets -maxdepth 1 -type f -exec cp -p {} $STAGE/state-index/$S/ \;      # per-state index
sudo chown -R $USER: $STAGE
cd $LIVE/.. && sudo find com.nintendo.zaba -type f -print0 | sudo xargs -0 -P12 -n200 sha256sum | sort -k2 > $STAGE/$S-full.sha256
```

The first round also copies `~/.local/share/waydroid/data/app/*/com.nintendo.zaba*/base.apk` to
`$STAGE/apk/feh-<version>.apk`. Once staging is done you can switch the in-game language. The drive copy
comes from `$STAGE`, so it doesn't matter that the game deletes the old language's files.

**d. Copy to the drive with tar over ssh** (run on the Mac, not `rsync`, see Quirks). The first round copies
the whole staging folder. Later rounds copy only that round's changed files:

```sh
ssh box 'tar -C ~/feh-dumper/dumps -cf - feh-<version>-<date>' | tar -C <drive>/dumps -xf -        # round 1
ssh box "cd $STAGE && { grep -v '/\$' changes-$S.list | sed 's|^|data/com.nintendo.zaba/|'; \
  printf '%s\n' $S-full.sha256 changes-$S.list state-index/$S; } | tar -cf - -T -" | tar -C <dest> -xf -
cd <dest>/data && shasum -a 256 -c ../$S-full.sha256 > ../verify-$S.out      # expect 0 failures, every round
```

**e. Finish.** On the box, build `MASTER-sha256sums.txt` (sha256 of every file under `$STAGE/data`). Copy it to
the drive, `shasum -c` it there, and check that the drive's file count (excluding `.DS_Store`) equals its
line count. Write `INFO.txt` in the same format as the previous dump, then `chmod -R a+rX,a-w` the dump
folder. Confirm the box's MASTER and the drive's MASTER have the same hash, then `rm -rf $STAGE`.

**f. Back to headless.** `bin/display --stop`. It stops the session, stops `feh-display`, and runs `bin/session`.
If you ever kill weston by hand, use `pkill -x weston`, not `pkill -f weston...`. Over SSH, `-f` also matches your
own remote shell (its command line contains the pattern) and kills it.

---

## Surviving a reboot

**Persists automatically** (nothing to do): the FEH data on disk
(`~/.local/share/waydroid/data/data/com.nintendo.zaba`); the binder devices (udev/module config from §0a);
the extra kernel modules (`/etc/modules-load.d/waydroid-feh.conf`, §0b); the UFW rules for `waydroid0` (§0c,
check with `sudo ufw status | grep waydroid`); the `waydroid-net.sh` nftables patch (a file edit, §2, which
`/usr/local/sbin/waydroid-net-patch` re-applies from an apt hook after every package operation, so a
`waydroid` upgrade can't silently revert it); `feh-display.service` (§5); and the `waydroid-container` service
(`systemctl enable`d).

**Does NOT persist — re-apply after each reboot before starting a session:**

1. **The Waydroid session.** It isn't a boot service. Run `bin/session` for headless or `bin/display` for the
   monitor, both over SSH; both also start PulseAudio if needed. The container service starts on boot, but the
   *session* (the user side that renders and connects) is started by hand.
2. **Only without UFW:** the runtime `nft insert` firewall rules (§0c) are gone after boot. Re-run them first,
   or the container gets no DHCP/internet.

So a clean "after reboot, play/dump again" is just `bin/display` over SSH. No keyboard needed.

---

## Changing the GPU

Written for, and used on 2026-10-29 for, the GTX 980 Ti → **Intel Arc A380** swap; the same steps apply to any
Mesa-driven card.
- **Swap-day results:** the Arc came up at `05:00.0` on i915, with DMC, GuC and HuC firmware loaded. There was no
  Resizable BAR on this board (a 256 MiB BAR), which doesn't matter here.
- After step 4, every check passed on the first try, and FEH ran visibly smoother than on nouveau.

The GPU is
picked at run time ([Quirks](#quirks--troubleshooting-everything-that-bit-us)), so nothing in this repo needs
editing. What changes is Android's view of the GPU, which Waydroid only writes when it regenerates its config.

1. **Before powering off:**
   - The new card's firmware must be installed. For Arc that's `firmware-intel-graphics` (non-free-firmware; it
     provides the GuC, HuC and DMC firmware), which the media server's `setup.sh` installs.
   - Keep a Waydroid restore point: a `tar --numeric-owner --acls --xattrs --xattrs-include='*'` of
     `/var/lib/waydroid` and `~/.local/share/waydroid`. On this box that's `/srv/backup`, from 2026-10-19.
2. **Swap the card.** Power off, fit the new card (the A380 needs a PCIe power cable), and move the monitor cable
   to its ports.
3. **Check the kernel side:** `lspci -k | grep -A3 -iE 'vga|display'` should show `Kernel driver in use: i915`.
   Then `ls -l /dev/dri/by-path`. The Arc sits behind its own PCIe switch, so its address isn't the old
   `03:00.0`, and that doesn't matter here.
4. **Regenerate Waydroid's config:** `sudo waydroid upgrade --offline`.
   - It rewrites the LXC config and `waydroid_base.prop` (`gralloc.gbm.device`, `ro.hardware.vulkan` → `intel`),
     stopping and restarting the container around that.
   - **Never run it without `--offline`:** that downloads a new LineageOS image, and the current one is the one
     known to work.
   - libhoudini's ABI properties live in `waydroid.cfg [properties]`, so they survive.
5. **`bin/session --props`** should show:
   - `arm64-v8a` in the ABI list and `libhoudini.so` as the native bridge
   - `gpu (host): i915, …`
   - `ro.hardware.vulkan: intel`
   - no `!!` lines
6. **`bin/display`:** FEH on the monitor, mouse working, and the game connects.
   - `grep 'GL renderer' /run/user/$UID/weston-feh.log` names the Intel GPU.
   - Then `bin/display --stop`.
7. **Optional: retry headless.** The headless hangs (§5) were only ever seen on nouveau. Run `bin/session`,
   launch FEH, and watch whether adbd and the container stay up. If they do, monitor mode becomes optional.
   - **Result on 2026-10-29:** FEH was tapped past its title screen with `input tap` and reached the animated home
     screen headless, with no hang and no crash. After about 60 s Waydroid froze the idle container (auto-suspend),
     so the 10-minute soak only proved about a minute of rendering.
   - **A real soak** needs the display kept awake first (e.g. `svc power stayon true` inside Android).
8. Once FEH is verified on the new card, delete the restore point (`sudo rm -rf /srv/backup`).

---

## Quirks & troubleshooting (everything that bit us)

- **adb says `device unauthorized`.** The image has `ro.adb.secure=1`, and Android has no stored host key
  (`/data/misc/adb` is empty).
  - The first `adb connect` from a host pops an **"Allow USB debugging?"** dialog on the Android screen, and adb stays
    unauthorized until it's answered. Tick **Always allow from this computer** (monitor mode, or `input tap`) to
    save the key.
  - It only matters for the adb scripts (`bin/dump`, `bin/shell`, `bin/logcat`, `bin/gsf-id`). The capture
    routine (§7) uses `sudo waydroid shell` instead.
- **adbd over TCP freezes** (device shows `offline`, `waydroid shell`/scrcpy hang). Only a full
  `waydroid session stop && waydroid session start` (i.e. `bin/session`) restores it — a
  `waydroid container restart` does **not**. The container itself usually keeps running; `sudo waydroid shell`
  (lxc-attach) and host-filesystem reads keep working through the freeze, so prefer them for anything scripted.
- **`waydroid shell` needs root**, and eats flags: use `sudo waydroid shell -- <cmd -flags>` (the `--` passes
  `-p`, `-b`, etc. through to the Android command).
- **Whole-tree `rsync` stalls** on the ~85k-file scan over a USB drive. The Mac's `/usr/bin/rsync` is
  **openrsync** (protocol 29), which is the likely culprit. Stream with **tar over ssh** instead (§7d), copying
  only each round's changed files, then **hash-verify the whole state** to catch anything missed. Over the
  Mac's Wi-Fi that runs at about 14 MB/s (8 GB in about 10 min).
- **Silent drive corruption** happens on flaky external drives — our per-round `shasum -c` caught a damaged
  `VOICE_*.ckb` that we re-copied. Always keep the manifests and re-verify.
- **Obfuscated-name files** (`SnZ77WFq`, `V9GiILGz`, `*~` in `files/assets/`) are FEH's mutable per-state asset
  catalog/index; they differ between language states — not corruption.
- **Networking must persist:** every container start re-runs `waydroid-net.sh`, so the `nft_masq`/`loop`
  modules and the `waydroid0` firewall rules must survive reboots or the session fails to boot again
  (`setup/00-host-prereqs.sh` persists both when UFW is active).
- **FEH comes back right after `am force-stop`.** Android can restart a background FEH process within
  milliseconds to run the Firebase telemetry job (logcat: `Start proc …:com.nintendo.zaba … for service
  {…datatransport…JobInfoSchedulerService}`). It isn't the game and only touches the telemetry database. Still,
  check `pidof` after stopping, force-stop again if needed, and re-run that round's rsync: on 2026-10-16 the
  re-sync found 0 changed files. Merge its output into `changes-$S.list` with `sort -u`.
- **Which GPU renders?** Check, don't assume: `bin/session --props` prints it on both sides. On this box it's the Arc
  A380 on **i915**. weston logs `GL renderer: Mesa Intel(R) Arc(tm) A380 Graphics (DG2)` (OpenGL ES 3.2, Mesa 25 on
  the host), and Android reports `ro.hardware.vulkan=intel`. Until 2026-10-29 it was the GTX 980 Ti on nouveau
  (`GL renderer: NV120`); see [Changing the GPU](#changing-the-gpu).
  - **How the GPU is picked:** `setup/feh-display/feh-gpu` uses Waydroid's own rule (`tools/helpers/gpu.py`): the
    first `/dev/dri/renderD*` whose kernel driver isn't `nvidia`. So weston and Android always pick the same card.
  - **To force one,** set `FEH_GPU=pci-…` (a `/dev/dri/by-path` id) in `/etc/default/feh-dumper`. If it differs from
    Waydroid's own pick, also set `drm_device` in `/var/lib/waydroid/waydroid.cfg`.
  - **Android's side is only written when Waydroid regenerates its config** (`gralloc.gbm.device` and
    `ro.hardware.vulkan` in `/var/lib/waydroid/waydroid_base.prop`). `bin/_gpu.sh` fails loudly when they don't
    match the host's GPU.
  - **Never install NVIDIA's proprietary driver.** It replaces nouveau, and Waydroid can't render on it: it falls
    back to software rendering, which hangs.
- **A one-off FEH crash after relaunch** (SIGSEGV on `GLThread`, in `libcocos2dcpp.so` at a `bl CkUpdate`,
  Cricket Audio's per-frame update) is **not** the emulator self-destruct. The log still says
  `isEmulator=false`; just relaunch. The self-destruct logs `isEmulator=true` first (README, Why emulators fail).
- **Interactive viewing:** scrcpy over an SSH tunnel to Waydroid's adb
  (`bin/screen` prints the recipe) works but rides on the flaky adbd —
  use the physical display for anything interactive (menus, sign-in, language switching).
