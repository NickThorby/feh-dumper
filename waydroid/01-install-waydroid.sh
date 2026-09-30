#!/usr/bin/env bash
# Install Waydroid + libhoudini (ARM translation) on Debian 13 for the FEH crash test.
# Run as root:  sudo bash ~/feh-waydroid/01-install-waydroid.sh
# Idempotent-ish; safe to re-run. Logs to ~/feh-waydroid/install.log too.
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive

# Log everything to a file (readable by nick) as well as the console.
exec > >(tee -a /home/nick/feh-waydroid/install.log) 2>&1

# --- 1. Waydroid apt repo + package ---------------------------------------
apt-get update -y
# weston = a Wayland compositor (box is headless; we run it headless for Waydroid to render into)
apt-get install -y curl ca-certificates git python3-venv lzip weston

# Official repo adder (writes /etc/apt/sources.list.d/waydroid.list + key)
curl -s https://repo.waydro.id | bash

# Debian 13 (trixie) may not have its own suite in the repo; fall back to bookworm.
apt-get update -y || {
  sed -i 's/ trixie / bookworm /' /etc/apt/sources.list.d/waydroid.list || true
  apt-get update -y
}
apt-get install -y waydroid || {
  sed -i 's/ trixie / bookworm /' /etc/apt/sources.list.d/waydroid.list || true
  apt-get update -y
  apt-get install -y waydroid
}

# --- 2. Initialise Waydroid (VANILLA image; ~1 GB download) ----------------
# -f re-inits if a previous attempt left partial state.
waydroid init -s VANILLA -f

# --- 3. Start the container service ----------------------------------------
systemctl enable --now waydroid-container
sleep 3
systemctl --no-pager status waydroid-container | head -5 || true

# --- 4. ARM translation: libhoudini via waydroid_script --------------------
cd /opt
if [ ! -d waydroid_script ]; then
  git clone https://github.com/casualsnek/waydroid_script
fi
cd waydroid_script
python3 -m venv venv
venv/bin/pip install -q --upgrade pip
venv/bin/pip install -q -r requirements.txt
# Non-interactive install of Intel's libhoudini (best on this i7 CPU).
venv/bin/python3 main.py install libhoudini

echo
echo "=== INSTALL DONE ==="
echo "libhoudini installed. Waydroid must be restarted for it to take effect;"
echo "the session step (run next, no sudo needed) will do that."
