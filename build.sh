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

echo "==> Lösche alten Build-Ordner..."
rm -rf build

echo "==> Wende RK3326 spezifische Python-Patches an..."
if [ -f "/work/patch_haloce_arm64.py" ]; then
  python3 /work/patch_haloce_arm64.py
fi

echo "==> Patche configure.py direkt für ARM64 (aarch64)..."
sed -i 's/--target=i686-linux-gnu/--target=aarch64-linux-gnu/g' configure.py
sed -i 's/-m32//g' configure.py
sed -i 's/-malign-double//g' configure.py

echo "==> Konfiguriere Build..."
python3 configure.py --lto=thin

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
