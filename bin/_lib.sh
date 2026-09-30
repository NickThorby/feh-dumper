# Shared by bin/*. DEVICE: adb serial (default: the ReDroid container on this host).
# For a phone over USB: DEVICE=<serial from `adb devices`> bin/dump
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PKG=com.nintendo.zaba            # Fire Emblem Heroes
DEVICE=${DEVICE:-localhost:5555}

adb_() { adb -s "$DEVICE" "$@"; }

connect() {
  if [[ $DEVICE == *:* ]]; then
    adb connect "$DEVICE" >/dev/null
  fi
  adb -s "$DEVICE" wait-for-device
}
