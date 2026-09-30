# Waydroid route — scripts

Reference scripts used to get FEH 10.9.0 running in Waydroid on a Debian 13 box (Intel i7-8700K / UHD 630).
See the top-level [README](../README.md#waydroid-route) for the overview and why this works when true
emulators don't. **For the full start-to-finish procedure on a fresh box — including the prerequisites these
scripts assume — follow [`RUNBOOK.md`](RUNBOOK.md).** This file is just the per-script reference.

> These were written for user `nick` on one box and hardcode paths like `/home/nick/...` and the Intel GPU.
> Adjust the paths/user for your setup. Run the `sudo` ones with root; run `physical-display.sh` at the
> **physical console** (not over SSH — it needs a logind seat for the DRM backend).

| Script | Run as | What it does |
|---|---|---|
| `01-install-waydroid.sh` | root | apt repo + `waydroid`, `weston`; `waydroid init -s VANILLA`; libhoudini via [waydroid_script](https://github.com/casualsnek/waydroid_script) |
| `03-netdeps.sh` | root | installs `iptables` + `dnsmasq-base` (Debian's `waydroid` pkg omits them) |
| `04-fix-net.sh` | root | patches `waydroid-net.sh` to the **nftables** backend (legacy iptables `mangle`/`CHECKSUM` is broken on trixie); backs up the original |
| `02-session.sh` | user | headless: starts `weston --backend=headless-backend.so` + a Waydroid session, prints ABIs / Build props (download-only; interactive use is unstable headless) |
| `restart-session.sh` | user | clean `waydroid session stop`/`start` — the only thing that reliably un-freezes adbd |
| `physical-display.sh` | user, **at the console** | moves Waydroid onto a real monitor via `weston --backend=drm-backend.so` (Intel GPU, hardware GL) — the stable way to interact |

## Prerequisites not scripted here

- Kernel needs the binder devices `binder,hwbinder,vndbinder` (this box already had them from the ReDroid
  `host/setup.sh`; on a fresh box create them, e.g. load `binder_linux` with `devices=binder,hwbinder,vndbinder`).
- Modules `nft_masq` and `loop` must be loaded (persist via `/etc/modules-load.d/`).
- Open the host firewall for the bridge:
  `sudo nft insert rule ip filter INPUT iifname "waydroid0" accept` and the same for
  `FORWARD` with `iifname`/`oifname` (UFW/Docker default-drop the bridge, which also blocks Android's DHCP).
- A headless box needs `pulseaudio` running for the user (the container bind-mounts the pulse socket).
- GApps + Google sign-in (device registered at google.com/android/uncertified) — FEH needs Play services.

## Gotcha cheat-sheet

- **adbd over TCP freezes** → `restart-session.sh` (a `container restart` does NOT fix it).
- **`waydroid shell` needs root** → `sudo waydroid shell` (or `-- <cmd>` to pass flags through).
- **Data is on the host** at `~/.local/share/waydroid/data/data/com.nintendo.zaba` — read it directly
  (survives adbd hangs); no adb/root-on-guest needed.
- **Whole-tree `rsync` stalls** on the ~85k-file scan over USB — rsync the specific new dir, then hash-verify.
