#!/bin/bash
# ============================================================
# Halo CE (halo-ce-universal) - Cross-Compile für ARM64 / RK3326
# ============================================================
set -e

export DEBIAN_FRONTEND=noninteractive
echo "==> Host arch: $(uname -m)"
dpkg --add-architecture arm64
apt-get update

echo "==> Installiere Build-Tools (Python, Ninja, Clang für arm64_32)"
apt-get install -y --no-install-recommends \
  build-essential git pkg-config ca-certificates wget zip \
  python3 ninja-build clang lld llvm \
  crossbuild-essential-arm64 \
  libsdl3-dev:arm64 \
  libgbm-dev:arm64 libegl1-mesa-dev:arm64 libgles2-mesa-dev:arm64 \
  libdrm-dev:arm64 libx11-dev:arm64 libasound2-dev:arm64 libpulse-dev:arm64

export SRC_DIR="/work/src"
export OUT_DIR="/work/out/haloce.aarch64"
mkdir -p "${SRC_DIR}" "${OUT_DIR}"

echo "==> Klone halo-ce-universal Decompilation"
cd "${SRC_DIR}"
git clone --depth=1 https://github.com/cybersecurity/halo-ce-universal.git
cd halo-ce-universal

echo "==> Wende RK3326 spezifische Python-Patches an"
python3 /work/patch_haloce_arm64.py

# Das Projekt nutzt Python + Ninja für den Build-Prozess.
# Wir zwingen das Script, die Android arm64_32 Guest-Umgebung für reines Linux zu kompilieren.
echo "==> Konfiguriere Build..."
python3 configure.py --lto=thin 

echo "==> Baue Halo CE..."
# Da das offizielle Linux-Target x86_64 ist, müssen wir Ninja anweisen,
# den Custom-Build (den wir im Python-Patch erstellen) auszuführen.
ninja linux_arm64_guest

# Kopiere das fertige Binary
cp build/linux_arm64/halo_ce_rk3326 "${OUT_DIR}/"
echo "==> Build erfolgreich."
