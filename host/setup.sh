#!/usr/bin/env bash
# One-time (and after every reinstall) host preparation for ReDroid on Debian. Idempotent.
#   sudo host/setup.sh
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run with sudo: sudo $0" >&2; exit 1; }

echo "== packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq adb lzip git curl python3-venv rsync >/dev/null

echo "== docker"
if ! command -v docker >/dev/null || ! docker compose version >/dev/null 2>&1; then
  echo "Docker with the compose plugin is required (the media server uses it too):" >&2
  echo "  https://docs.docker.com/engine/install/debian/" >&2
  exit 1
fi
docker --version

echo "== binder (Android IPC; Debian ships it as a module, no binderfs)"
echo "options binder_linux devices=binder,hwbinder,vndbinder" > /etc/modprobe.d/feh-dumper-binder.conf
echo "binder_linux" > /etc/modules-load.d/feh-dumper-binder.conf
if [[ -e /dev/binder && ! -e /dev/hwbinder ]]; then
  # loaded earlier with the default single device: reload with all three
  rmmod binder_linux || { echo "binder_linux is in use; stop containers using it and re-run" >&2; exit 1; }
fi
modprobe binder_linux
# Android's services (servicemanager runs as uid 1000, not root) must open the devices; Debian
# creates them root-only (0600), which leaves Android stuck at boot ("Binder driver could not be opened").
echo 'KERNEL=="binder|hwbinder|vndbinder", MODE="0666"' > /etc/udev/rules.d/99-feh-dumper-binder.rules
udevadm control --reload-rules
chmod 666 /dev/binder /dev/hwbinder /dev/vndbinder
for d in binder hwbinder vndbinder; do
  [[ -e /dev/$d ]] || { echo "missing /dev/$d after loading binder_linux" >&2; exit 1; }
done
ls -l /dev/binder /dev/hwbinder /dev/vndbinder

# Android 11 in ReDroid wants ashmem; this kernel has none (removed upstream in 5.18), so compose.yaml
# boots with androidboot.use_memfd=true instead.

echo "OK: host ready. Next: image/build.sh (as your user, in the docker group)"
