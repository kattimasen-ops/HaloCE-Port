#!/bin/bash
# ============================================================
# Halo CE (halo-ce-universal) - Cross-Compile für ARM64 / RK3326
# ============================================================
set -e

export DEBIAN_FRONTEND=noninteractive
echo "==> Host arch: $(uname -m)"

# APT Update
apt-get update

echo "==> Installiere Build-Tools & ARM64 Cross-Compiler"
apt-get install -y --no-install-recommends \
  build-essential git pkg-config ca-certificates wget zip \
  python3 ninja-build clang lld llvm cmake \
  gcc-aarch64-linux-gnu g++-aarch64-linux-gnu crossbuild-essential-arm64 \
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
if [ -f "/work/patch_haloce_arm64.py" ]; then
  python3 /work/patch_haloce_arm64.py
fi

echo "==> Ermittle gepatchtes ARM64-Target für configure.py..."
TARGET_ARG=""
if python3 configure.py --help 2>&1 | grep -q "linux_arm64"; then
  TARGET_ARG="--target=linux_arm64"
elif python3 configure.py --help 2>&1 | grep -q "linux_arm64_32"; then
  TARGET_ARG="--target=linux_arm64_32"
elif python3 configure.py --help 2>&1 | grep -q "linux_aarch64"; then
  TARGET_ARG="--target=linux_aarch64"
elif python3 configure.py --help 2>&1 | grep -q "arm64"; then
  TARGET_ARG="--target=arm64"
elif python3 configure.py --help 2>&1 | grep -q "rk3326"; then
  TARGET_ARG="--target=rk3326"
fi

echo "==> Konfiguriere Build mit Target: ${TARGET_ARG:-default}"
python3 configure.py ${TARGET_ARG} --lto=thin

echo "==> Baue Halo CE..."
ninja

echo "==> Suche und kopiere kompilierte Executable..."
mkdir -p "${OUT_DIR}"

BINARY_PATH=$(find build -type f -executable -name "halo_ce*" -o -name "halo*" | head -n 1)

if [ -n "$BINARY_PATH" ]; then
  cp "$BINARY_PATH" "${OUT_DIR}/halo_ce_rk3326"
  echo "==> Binary erfolgreich kopiert: $BINARY_PATH -> ${OUT_DIR}/halo_ce_rk3326"
else
  echo "❌ FEHLER: Keine kompilierte Executable im Ordner 'build' gefunden!"
  exit 1
fi

echo "==> Build erfolgreich beendet."
