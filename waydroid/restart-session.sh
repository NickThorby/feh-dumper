#!/usr/bin/env bash
export XDG_RUNTIME_DIR=/run/user/1000 WAYLAND_DISPLAY=wayland-waydroid
[ -S $XDG_RUNTIME_DIR/bus ] && export DBUS_SESSION_BUS_ADDRESS=unix:path=$XDG_RUNTIME_DIR/bus
echo RESTARTING > ~/feh-waydroid/restart.status
sudo waydroid shell -- setprop persist.adb.tcp.port 5555 2>/dev/null
waydroid session stop 2>/dev/null; sleep 3
[ -S $XDG_RUNTIME_DIR/pulse/native ] || pulseaudio --start --exit-idle-time=-1 2>/dev/null
[ -S $XDG_RUNTIME_DIR/$WAYLAND_DISPLAY ] || { nohup weston --backend=headless-backend.so --socket=$WAYLAND_DISPLAY --width=720 --height=1280 --idle-time=0 >~/feh-waydroid/weston.log 2>&1 & sleep 4; }
nohup waydroid session start >~/feh-waydroid/session.log 2>&1 &
for i in $(seq 1 48); do
  b=$(sudo waydroid shell getprop sys.boot_completed 2>/dev/null | tr -d '\n')
  [ "$b" = 1 ] && { echo BOOTED > ~/feh-waydroid/restart.status; exit 0; }
  sleep 5
done
echo TIMEOUT > ~/feh-waydroid/restart.status
