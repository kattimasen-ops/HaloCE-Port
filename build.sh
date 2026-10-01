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

echo "==> 1. Erster configure.py Aufruf (Downloads & Git-Checkout)..."
python3 configure.py --lto=thin || true

echo "==> 2. Deaktiviere automatisches Git-Reset..."
sed -i 's/git checkout/echo skipping git checkout/g' configure.py

echo "==> 3. Wende RK3326 spezifische Python-Patches an..."
if [ -f "/work/patch_haloce_arm64.py" ]; then
  python3 /work/patch_haloce_arm64.py
fi

echo "==> 4. Patche configure.py auf ARM64 (aarch64)..."
sed -i 's/i686-linux-gnu/aarch64-linux-gnu/g' configure.py
sed -i 's/-m32//g' configure.py
sed -i 's/-malign-double//g' configure.py
sed -i 's/-freg-struct-return//g' configure.py
sed -i 's/-march=native/-mcpu=cortex-a35/g' configure.py

echo "==> 5. Regeneriere Build-Dateien..."
python3 configure.py --lto=thin

echo "==> 6. Sichere globale Ersetzung in ALLEN .ninja-Dateien..."
find . -name "*.ninja" -exec sed -i 's/--target=i686-linux-gnu/--target=aarch64-linux-gnu --sysroot=\/usr\/aarch64-linux-gnu/g' {} +
find . -name "*.ninja" -exec sed -i 's/-m32//g' {} +
find . -name "*.ninja" -exec sed -i 's/-malign-double//g' {} +
find . -name "*.ninja" -exec sed -i 's/-freg-struct-return//g' {} +
find . -name "*.ninja" -exec sed -i 's/-march=native/-mcpu=cortex-a35/g' {} +

echo "==> 7. Baue Halo CE..."
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
