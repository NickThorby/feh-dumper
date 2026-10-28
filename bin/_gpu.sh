# Shared by bin/session and bin/display (both set ROOT first): the GPU Waydroid renders on, and a check that Android
# agrees. setup/feh-display/feh-gpu picks it by Waydroid's own rule (the first render node not driven by nvidia;
# FEH_GPU in /etc/default/feh-dumper overrides it), so a GPU swap needs no edit. What a swap does leave stale is
# Android's GPU properties, until `sudo waydroid upgrade --offline` regenerates them: gralloc_ok catches that.
if [[ -r /etc/default/feh-dumper ]]; then set -a; source /etc/default/feh-dumper; set +a; fi
if ! _gpu=$("$ROOT/setup/feh-display/feh-gpu"); then exit 1; fi   # feh-gpu says why
read -r GPU_RENDER GPU_CARD GPU_DRIVER <<<"$_gpu"
GPU_PCI=$(basename "$(readlink -f "/sys/class/drm/${GPU_RENDER##*/}/device")")

# The ro.hardware.vulkan Waydroid derives from a kernel driver (its gpu.py getVulkanDriver; pre-gen9 Intel, which
# Waydroid maps to intel_hasvk, isn't a concern on this box).
gpu_vulkan() {
  case $1 in
    i915|xe) echo intel ;; amdgpu|radeon) echo radeon ;; nouveau) echo nouveau ;;
    panfrost) echo panfrost ;; msm|msm_dpu) echo freedreno ;; vc4) echo broadcom ;;
  esac
}

# gralloc_ok: Android's gralloc must use this GPU's render node and its Vulkan HAL must match the driver; prints any
# mismatch with the fix and fails otherwise.
gralloc_ok() {
  local dev vk want bad=0
  dev=$(sudo waydroid shell -- getprop gralloc.gbm.device 2>/dev/null | tr -d '\r\n')
  vk=$(sudo waydroid shell -- getprop ro.hardware.vulkan 2>/dev/null | tr -d '\r\n')
  want=$(gpu_vulkan "$GPU_DRIVER")
  [[ $dev == "$GPU_RENDER" ]] || { echo "!! Android's gralloc uses '${dev:-?}', not $GPU_RENDER ($GPU_DRIVER, $GPU_PCI)." >&2; bad=1; }
  [[ $vk == "$want" ]] || { echo "!! Android's ro.hardware.vulkan is '${vk:-?}', not '$want' for $GPU_DRIVER." >&2; bad=1; }
  (( bad == 0 )) && return 0
  echo "   After a GPU change: sudo waydroid upgrade --offline (never without --offline: that downloads a new image)." >&2
  return 1
}
