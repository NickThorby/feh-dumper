#!/usr/bin/env bash
# Waydroid networking deps missing on Debian 13; install them.
# Run as root:  sudo bash /home/nick/feh-waydroid/03-netdeps.sh
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
exec > >(tee -a /home/nick/feh-waydroid/netdeps.log) 2>&1

apt-get install -y iptables dnsmasq-base
# Debian 13 uses the nft backend; make sure the iptables alternative resolves.
update-alternatives --set iptables /usr/sbin/iptables-nft 2>/dev/null || true
update-alternatives --set ip6tables /usr/sbin/ip6tables-nft 2>/dev/null || true

command -v iptables dnsmasq
iptables --version
echo "=== NETDEPS DONE ==="
