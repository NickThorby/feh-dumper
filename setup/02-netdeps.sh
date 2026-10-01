#!/usr/bin/env bash
# Waydroid networking deps missing on Debian 13; install them.
#   sudo setup/02-netdeps.sh
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$ROOT/logs"; [[ -n ${SUDO_USER:-} ]] && chown "$SUDO_USER:" "$ROOT/logs"   # bin/session logs there too
exec > >(tee -a "$ROOT/logs/netdeps.log") 2>&1

apt-get install -y iptables dnsmasq-base
# Debian 13 uses the nft backend; make sure the iptables alternative resolves.
update-alternatives --set iptables /usr/sbin/iptables-nft 2>/dev/null || true
update-alternatives --set ip6tables /usr/sbin/ip6tables-nft 2>/dev/null || true

command -v iptables dnsmasq
iptables --version
echo "=== NETDEPS DONE ==="
