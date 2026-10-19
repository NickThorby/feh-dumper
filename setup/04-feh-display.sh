#!/usr/bin/env bash
# Install feh-display.service: weston on the physical monitor as the invoking user on tty9, which bin/display
# starts and stops over SSH. Replaces logging in at the console (no keyboard needed). Edit GPU in
# setup/feh-display/weston-feh and bin/_gpu.sh together if the box's GPU changes.
#   sudo setup/04-feh-display.sh
set -euo pipefail
[[ $EUID -eq 0 && -n ${SUDO_USER:-} ]] || { echo "run with sudo from your user: sudo $0" >&2; exit 1; }
D=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/feh-display

install -d -m 0755 /usr/local/lib/feh-display
install -m 0755 "$D/weston-feh" "$D/vt-back" /usr/local/lib/feh-display/
install -m 0644 "$D/pam-feh-display" /etc/pam.d/feh-display
sed "s/^User=.*/User=$SUDO_USER/; s/^Group=.*/Group=$(id -gn "$SUDO_USER")/; s|^WorkingDirectory=.*|WorkingDirectory=$(getent passwd "$SUDO_USER" | cut -d: -f6)|" \
  "$D/feh-display.service" > /etc/systemd/system/feh-display.service
systemctl daemon-reload
systemd-analyze verify /etc/systemd/system/feh-display.service
echo "OK: feh-display.service installed for $SUDO_USER. Test: bin/display (monitor connected), then bin/display --stop"
