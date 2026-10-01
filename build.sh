#!/bin/bash
# ============================================================
# Halo CE (halo-ce-universal) - Cross-Compile für ARM64 / RK3326
# ============================================================
set -e

export DEBIAN_FRONTEND=noninteractive
echo "==> Host arch: $(uname -m)"

# APT Update (Quellen wurden bereits vom YAML-Workflow eingerichtet)
apt-get update

echo "==> Installiere Build-Tools (Python, Ninja, Clang für arm64_32)"
# libsdl3-dev:arm64 wurde entfernt, da SDL3 bereits im YAML gebaut wurde
apt-get install -y --no-install-recommends \
  build-essential git pkg-config ca-certificates wget zip \
  python3 ninja-build clang lld llvm \
  crossbuild-essential-arm64 \
  libgbm-dev:arm64 libegl1-mesa-dev:arm64 libgles2-mesa-dev:arm64 \
  libdrm-dev:arm64 libx11-dev:arm64 libasound2-dev:arm64 libpulse-dev:arm64

export SRC_DIR="/work/src"
export OUT_DIR="/work/out/haloce.aarch64"
mkdir -p "${SRC_DIR}" "${OUT_DIR}"

echo "==> Klone halo-ce-universal Decompilation"
cd "${SRC_DIR}"
if [ ! -d "halo-ce-universal" ]; then
  git clone --depth=1 https://github.com/cybersecurity/halo-ce-universal.git
fi
cd halo-ce-universal

echo "==> Wende RK3326 spezifische Python-Patches an"
python3 /work/patch_haloce_arm64.py

echo "==> Konfiguriere Build..."
python3 configure.py --lto=thin 

echo "==> Baue Halo CE..."
ninja linux_rk3326_guest

# Kopiere das fertige Binary in den Output-Ordner
mkdir -p "${OUT_DIR}"
cp build/linux_rk3326/halo_ce "${OUT_DIR}/halo_ce_rk3326"

echo "==> Build erfolgreich beendet."
