#!/usr/bin/env bash
# Build the Android image: ReDroid + Google apps + ARM translation (FEH ships ARM code only).
# Uses ayasa520/redroid-script, pinned. Variants (if the game won't run on the default):
#   image/build.sh                                  11.0.0 + OpenGapps + libndk   (default)
#   TRANSLATION=houdini image/build.sh              11.0.0 + OpenGapps + libhoudini
#   ANDROID=12.0.0 GAPPS=mindthegapps image/build.sh  (OpenGapps is 11-only)
# Writes FEH_IMAGE=<tag> to .env, which compose.yaml reads.
set -euo pipefail
cd "$(dirname "$0")/.."

ANDROID=${ANDROID:-11.0.0}
TRANSLATION=${TRANSLATION:-ndk}        # ndk | houdini
GAPPS=${GAPPS:-gapps}                  # gapps | mindthegapps | litegapps
SCRIPT_REPO=https://github.com/ayasa520/redroid-script
SCRIPT_COMMIT=a4951b782fc8e06c845d9553bf07bb643fd8c158

command -v lzip >/dev/null || { echo "lzip missing: run sudo host/setup.sh" >&2; exit 1; }
work=.build/redroid-script
if [[ ! -d $work/.git ]]; then
  git clone -q "$SCRIPT_REPO" "$work"
fi
git -C "$work" fetch -q origin "$SCRIPT_COMMIT" 2>/dev/null || true
git -C "$work" checkout -q "$SCRIPT_COMMIT"
python3 -m venv .build/venv
.build/venv/bin/pip install -q -r "$work/requirements.txt"

flags=(-a "$ANDROID")
case $GAPPS in gapps) flags+=(-g) ;; mindthegapps) flags+=(-mtg) ;; litegapps) flags+=(-lg) ;;
  *) echo "GAPPS must be gapps|mindthegapps|litegapps" >&2; exit 1 ;; esac
case $TRANSLATION in ndk) flags+=(-n) ;; houdini) flags+=(-i) ;;
  *) echo "TRANSLATION must be ndk|houdini" >&2; exit 1 ;; esac

(cd "$work" && ../venv/bin/python redroid.py "${flags[@]}")

# redroid-script tags redroid/redroid:<version>_<parts>; give it our own name too
built="redroid/redroid:${ANDROID}_${GAPPS}_${TRANSLATION}"
tag="feh-android:${ANDROID}_${GAPPS}_${TRANSLATION}"
docker image inspect "$built" >/dev/null || { echo "build failed: $built not found" >&2; exit 1; }
docker tag "$built" "$tag"
{ grep -v '^FEH_IMAGE=' .env 2>/dev/null || true; echo "FEH_IMAGE=$tag"; } > .env.tmp && mv .env.tmp .env
echo "OK: $tag (in .env). Next: bin/up"
