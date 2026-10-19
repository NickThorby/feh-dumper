#!/usr/bin/env bash
# Make Waydroid networking use the nftables backend (trixie kernel has no working legacy iptables
# mangle/CHECKSUM). Installs setup/waydroid-net-patch plus an apt hook that re-applies it whenever a
# waydroid package upgrade reverts it, applies it now, and restarts the bridge to prove it works.
#   sudo setup/03-fix-net.sh
set -euxo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$ROOT/logs"; [[ -n ${SUDO_USER:-} ]] && chown "$SUDO_USER:" "$ROOT/logs"   # bin/session logs there too
exec > >(tee -a "$ROOT/logs/fixnet.log") 2>&1
SCRIPT=/usr/lib/waydroid/data/scripts/waydroid-net.sh

cp -n "$SCRIPT" "${SCRIPT}.orig"          # one-time backup
install -m 0755 "$ROOT/setup/waydroid-net-patch" /usr/local/sbin/waydroid-net-patch
echo 'DPkg::Post-Invoke { "if [ -x /usr/local/sbin/waydroid-net-patch ]; then /usr/local/sbin/waydroid-net-patch || true; fi"; };' \
  > /etc/apt/apt.conf.d/99waydroid-net-patch
/usr/local/sbin/waydroid-net-patch
grep -n 'LXC_USE_NFT=' "$SCRIPT"

# Bring networking up now to prove it works.
"$SCRIPT" stop force 2>/dev/null || true
"$SCRIPT" start

echo "=== bridge ==="; ip -4 addr show waydroid0 | grep -E "waydroid0|inet" || true
echo "=== nft lxc tables ==="; nft list tables | grep lxc || true
echo "=== FIXNET DONE ==="
