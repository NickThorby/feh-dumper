#!/usr/bin/env bash
# Run this AT THE PHYSICAL CONSOLE (after logging in as nick on the monitor), NOT over SSH.
# It moves Waydroid from the headless renderer onto the real monitor (Intel GPU) with kbd/mouse.
set -u
export XDG_RUNTIME_DIR=/run/user/$(id -u)
echo ">>> stopping headless session..."
waydroid session stop 2>/dev/null
pkill -f 'weston.*wayland-waydroid' 2>/dev/null
sleep 3
echo ">>> starting weston on the physical monitor (Intel GPU)..."
nohup weston --backend=drm-backend.so --socket=wayland-waydroid --idle-time=0 >~/feh-waydroid/weston-drm.log 2>&1 &
sleep 6
export WAYLAND_DISPLAY=wayland-waydroid
if [ ! -S "$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY" ]; then
  echo "!! weston did not create its socket. See ~/feh-waydroid/weston-drm.log:"; tail -5 ~/feh-waydroid/weston-drm.log; exit 1
fi
echo ">>> starting Waydroid session..."
nohup waydroid session start >~/feh-waydroid/session.log 2>&1 &
echo ">>> waiting for Android to boot (up to ~4 min)..."
for i in $(seq 1 48); do
  [ "$(sudo waydroid shell getprop sys.boot_completed 2>/dev/null | tr -d '\r\n')" = 1 ] && { echo "booted"; break; }
  sleep 5
done
waydroid show-full-ui >/dev/null 2>&1 &
sleep 4
sudo waydroid shell -- am start -n com.nintendo.zaba/org.cocos2dx.cpp.AppActivity >/dev/null 2>&1
echo ">>> FEH should now be on the monitor. Use the keyboard & mouse."
echo ">>> Change the language/region to EU English, then tell Claude to capture it."
