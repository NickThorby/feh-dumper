#!/usr/bin/env bash
# Start a headless Wayland compositor + Waydroid session, then report ABIs and Build props.
# Run as the normal user (nick), NOT root:  bash ~/feh-waydroid/02-session.sh
set -uxo pipefail
export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
[ -S "$XDG_RUNTIME_DIR/bus" ] && export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"
cd ~/feh-waydroid

# --- headless weston (only if no compositor already up) --------------------
export WAYLAND_DISPLAY=wayland-waydroid
if [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
  nohup weston --backend=headless-backend.so --socket="$WAYLAND_DISPLAY" \
        --width=720 --height=1280 --idle-time=0 >weston.log 2>&1 &
  sleep 4
fi
echo "weston socket: $(ls -l $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY 2>&1)"

# --- Waydroid session ------------------------------------------------------
waydroid session stop 2>/dev/null || true
nohup waydroid session start >session.log 2>&1 &
# wait for Android userspace to finish booting
for i in $(seq 1 40); do
  b=$(waydroid shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')
  echo "boot_completed=$b (try $i)"
  [ "$b" = 1 ] && break
  sleep 5
done

echo "=== STATUS ==="; waydroid status 2>&1 | head
echo "=== ABIs (must include arm64-v8a for libhoudini) ==="
waydroid shell getprop ro.product.cpu.abilist 2>&1
waydroid shell getprop ro.product.cpu.abilist64 2>&1
echo "=== Build identity (the isEmulator variable) ==="
for p in ro.product.model ro.product.name ro.product.brand ro.product.device \
         ro.build.fingerprint ro.build.tags ro.build.type; do
  echo "$p = $(waydroid shell getprop $p 2>&1 | tr -d '\r')"
done
echo "=== native bridge (ARM translation) ==="
waydroid shell getprop ro.dalvik.vm.native.bridge 2>&1
