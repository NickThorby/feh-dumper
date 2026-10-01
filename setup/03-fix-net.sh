#!/usr/bin/env bash
# Make Waydroid networking use the nftables backend (trixie kernel has no working
# legacy iptables mangle/CHECKSUM). Re-run after a waydroid package upgrade (it reverts the patch).
#   sudo setup/03-fix-net.sh
set -euxo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$ROOT/logs"; [[ -n ${SUDO_USER:-} ]] && chown "$SUDO_USER:" "$ROOT/logs"   # bin/session logs there too
exec > >(tee -a "$ROOT/logs/fixnet.log") 2>&1
SCRIPT=/usr/lib/waydroid/data/scripts/waydroid-net.sh

cp -n "$SCRIPT" "${SCRIPT}.orig"          # one-time backup
sed -i 's/^LXC_USE_NFT="false"/LXC_USE_NFT="true"/' "$SCRIPT"
grep -n 'LXC_USE_NFT=' "$SCRIPT"

# Fix the stray leading ';' in the nft ruleset when IPv6 NAT is off (Waydroid bug).
python3 - "$SCRIPT" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s2 = s.replace('NFT_RULESET="${NFT_RULESET};', 'NFT_RULESET="${NFT_RULESET}')
# Feed nft on stdin instead of as one big (blank-line-leading) argument.
s2 = s2.replace('nft "${NFT_RULESET}"', 'echo "${NFT_RULESET}" | tee /tmp/waydroid-nft.rules | nft -f -')
if s2 != s:
    open(p, "w").write(s2); print("patched nft invocation / semicolon")
else:
    print("nft patches: already applied / not found")
PY

# Bring networking up now to prove it works.
"$SCRIPT" stop force 2>/dev/null || true
"$SCRIPT" start

echo "=== bridge ==="; ip -4 addr show waydroid0 | grep -E "waydroid0|inet" || true
echo "=== nft lxc tables ==="; nft list tables | grep lxc || true
echo "=== FIXNET DONE ==="
