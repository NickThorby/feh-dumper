# Shared by bin/session and bin/display: the GPU Waydroid must render on, and a check that it does.
# The box's only working GPU is the GTX 980 Ti at PCI 03:00.0, driven by nouveau (Mesa); its Intel iGPU is off in
# the BIOS. Waydroid needs a Mesa driver: it can't render on NVIDIA's proprietary driver, and headless software
# rendering hangs FEH. Keep GPU in sync with /usr/local/lib/feh-display/weston-feh on the box.
GPU=pci-0000:03:00.0

# gralloc_ok: Android's gralloc must use this GPU's render node; prints the mismatch and fails otherwise.
gralloc_ok() {
  local want have
  want=/dev/dri/$(basename "$(readlink -f "/dev/dri/by-path/$GPU-render")")
  have=$(sudo waydroid shell -- getprop gralloc.gbm.device 2>/dev/null | tr -d '\r\n')
  [[ $have == "$want" ]] && return 0
  echo "!! Waydroid renders on '${have:-?}', not $want ($GPU). See RUNBOOK quirks (gralloc.gbm.device)." >&2
  return 1
}
