#!/usr/bin/env bash
# Host preparation Waydroid needs on Debian 13 before it's installed: packages, binder devices,
# kernel modules, and a firewall opening for the waydroid0 bridge. Idempotent; persists across reboots.
#   sudo setup/00-host-prereqs.sh
set -euo pipefail

[[ $EUID -eq 0 ]] || { echo "run with sudo: sudo $0" >&2; exit 1; }
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$ROOT/logs"; [[ -n ${SUDO_USER:-} ]] && chown "$SUDO_USER:" "$ROOT/logs"   # bin/session logs there too
exec > >(tee -a "$ROOT/logs/host-prereqs.log") 2>&1

echo "== packages"
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
# pulseaudio: the container bind-mounts the user's pulse socket and won't start without it, even headless
apt-get install -y -qq adb rsync python3 pulseaudio >/dev/null

echo "== binder (Android IPC; Debian ships it as a module, no binderfs)"
echo "options binder_linux devices=binder,hwbinder,vndbinder" > /etc/modprobe.d/waydroid-binder.conf
echo "binder_linux" > /etc/modules-load.d/waydroid-binder.conf
if [[ -e /dev/binder && ! -e /dev/hwbinder ]]; then
  # loaded earlier with the default single device: reload with all three
  rmmod binder_linux || { echo "binder_linux is in use; stop Waydroid (waydroid container stop) and re-run" >&2; exit 1; }
fi
modprobe binder_linux
# Android's services (servicemanager runs as uid 1000, not root) must open the devices; Debian
# creates them root-only (0600), which leaves Android stuck at boot ("Binder driver could not be opened").
echo 'KERNEL=="binder|hwbinder|vndbinder", MODE="0666"' > /etc/udev/rules.d/99-waydroid-binder.rules
udevadm control --reload-rules
chmod 666 /dev/binder /dev/hwbinder /dev/vndbinder
for d in binder hwbinder vndbinder; do
  [[ -e /dev/$d ]] || { echo "missing /dev/$d after loading binder_linux" >&2; exit 1; }
done
ls -l /dev/binder /dev/hwbinder /dev/vndbinder

echo "== kernel modules (loop: mount system.img; nft_masq & co: the container's NAT)"
mods=(loop nf_nat nft_nat nft_masq nft_chain_nat)
printf '%s\n' "${mods[@]}" > /etc/modules-load.d/waydroid-feh.conf
modprobe -a "${mods[@]}"

echo "== firewall: open the waydroid0 bridge (UFW/Docker default-drop it: no DHCP, no internet)"
if command -v ufw >/dev/null && ufw status | grep -q '^Status: active'; then
  ufw allow in on waydroid0            # INPUT: DHCP/DNS from the container to the host
  ufw route allow in on waydroid0      # FORWARD: container -> internet
  ufw route allow out on waydroid0     # FORWARD: replies back to the container
else
  echo "UFW not active: these runtime rules do not survive a reboot; re-run them before each session:"
  echo '  sudo nft insert rule ip filter INPUT   iifname "waydroid0" accept'
  echo '  sudo nft insert rule ip filter FORWARD iifname "waydroid0" accept'
  echo '  sudo nft insert rule ip filter FORWARD oifname "waydroid0" accept'
fi

echo "OK: host ready. Next: sudo setup/01-install-waydroid.sh"
