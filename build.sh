#!/bin/bash
# ============================================================
# Halo CE (halo-ce-universal) - Cross-Compile für ARM64 / RK3326
# Host: Ubuntu 24.04 x86_64
# Target: ARM64 / Cortex-A35 / RK3326
# ============================================================

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "============================================================"
echo "Halo CE ARM64 Cross-Compilation"
echo "============================================================"
echo "==> Host arch: $(uname -m)"

# ------------------------------------------------------------
# 1. APT / Build-Abhängigkeiten
# ------------------------------------------------------------

echo "==> APT Update..."
apt-get update

echo "==> Installiere Build-Tools & ARM64 Cross-Compiler..."

apt-get install -y --no-install-recommends \
    build-essential \
    git \
    pkg-config \
    ca-certificates \
    wget \
    zip \
    python3 \
    ninja-build \
    clang \
    lld \
    llvm \
    cmake \
    gcc-aarch64-linux-gnu \
    g++-aarch64-linux-gnu \
    crossbuild-essential-arm64 \
    libgbm-dev:arm64 \
    libegl1-mesa-dev:arm64 \
    libgles2-mesa-dev:arm64 \
    libdrm-dev:arm64 \
    libx11-dev:arm64 \
    libasound2-dev:arm64 \
    libpulse-dev:arm64

# ------------------------------------------------------------
# 2. Verzeichnisse
# ------------------------------------------------------------

export SRC_DIR="/work/src"
export OUT_DIR="/work/out/haloce.aarch64"

mkdir -p "${SRC_DIR}"
mkdir -p "${OUT_DIR}"

# ------------------------------------------------------------
# 3. Repository
# ------------------------------------------------------------

echo "==> Klone halo-ce-universal..."

cd "${SRC_DIR}"

if [ ! -d "halo-ce-universal/.git" ]; then
    rm -rf halo-ce-universal

    git clone --depth=1 \
        https://github.com/cybersecurity/halo-ce-universal.git \
        halo-ce-universal
else
    echo "==> Repository bereits vorhanden."
fi

cd halo-ce-universal

# ------------------------------------------------------------
# 4. Erster configure.py Aufruf
#
# Dieser Aufruf darf den initialen Git-Checkout und die
# Downloads/Abhängigkeiten durchführen.
#
# Ein Fehler wird hier bewusst ignoriert, weil configure.py
# möglicherweise nur zum Initialisieren/Herunterladen
# verwendet wird.
# ------------------------------------------------------------

echo "==> 1. Erster configure.py Aufruf..."
python3 configure.py --lto=thin || true

# ------------------------------------------------------------
# 5. Automatischen Git-Checkout deaktivieren
#
# configure.py darf unsere nachfolgenden ARM64-Änderungen
# nicht wieder durch den ursprünglichen x86-Stand ersetzen.
# ------------------------------------------------------------

echo "==> 2. Deaktiviere automatisches Git-Checkout..."

if grep -q "git checkout" configure.py; then
    sed -i \
        's/git checkout/echo skipping git checkout/g' \
        configure.py
else
    echo "==> Kein 'git checkout' mehr in configure.py gefunden."
fi

# ------------------------------------------------------------
# 6. Externes ARM64-Patch-Skript ausführen
# ------------------------------------------------------------

echo "==> 3. Wende RK3326-spezifische Python-Patches an..."

if [ -f "/work/patch_haloce_arm64.py" ]; then
    python3 /work/patch_haloce_arm64.py
else
    echo "==> Kein externes Patch-Skript gefunden."
fi

# ------------------------------------------------------------
# 7. ARM64 Cross-Compilation in configure.py erzwingen
# ------------------------------------------------------------

echo "==> 4. Patche configure.py auf ARM64..."

sed -i \
    's/i686-linux-gnu/aarch64-linux-gnu/g' \
    configure.py

sed -i \
    's/-m32//g' \
    configure.py

sed -i \
    's/-malign-double//g' \
    configure.py

sed -i \
    's/-freg-struct-return//g' \
    configure.py

sed -i \
    's/-march=native/-mcpu=cortex-a35/g' \
    configure.py

# ------------------------------------------------------------
# 8. Sicherheitsprüfung configure.py
# ------------------------------------------------------------

echo "==> 5. Prüfe configure.py auf verbliebene x86-Flags..."

if grep -nE \
    -- '--target=i686-linux-gnu|-m32|-malign-double|-freg-struct-return|-march=native' \
    configure.py; then

    echo "❌ FEHLER: configure.py enthält noch unerlaubte x86-Flags."
    exit 1
else
    echo "==> configure.py enthält keine bekannten x86-Flags mehr."
fi

# ------------------------------------------------------------
# 9. Build-Dateien neu erzeugen
# ------------------------------------------------------------

echo "==> 6. Regeneriere Ninja-Build-Dateien..."

python3 configure.py --lto=thin

# ------------------------------------------------------------
# 10. Alle generierten Ninja-Dateien ARM64-kompatibel machen
#
# Wichtig:
# configure.py erzeugt build.ninja im Root UND weitere
# .ninja-Dateien unterhalb von build/.
# ------------------------------------------------------------

echo "==> 7. Patche ALLE .ninja-Dateien..."

NINJA_FILES=$(find . -type f -name "*.ninja")

if [ -z "${NINJA_FILES}" ]; then
    echo "❌ FEHLER: Keine .ninja-Dateien gefunden."
    exit 1
fi

while IFS= read -r ninja_file; do

    echo "==> Patch: ${ninja_file}"

    sed -i \
        's/--target=i686-linux-gnu/--target=aarch64-linux-gnu --sysroot=\/usr\/aarch64-linux-gnu/g' \
        "${ninja_file}"

    sed -i \
        's/-m32//g' \
        "${ninja_file}"

    sed -i \
        's/-malign-double//g' \
        "${ninja_file}"

    sed -i \
        's/-freg-struct-return//g' \
        "${ninja_file}"

    sed -i \
        's/-march=native/-mcpu=cortex-a35/g' \
        "${ninja_file}"

done <<< "${NINJA_FILES}"

# ------------------------------------------------------------
# 11. Sicherheitsprüfung aller Ninja-Dateien
# ------------------------------------------------------------

echo "==> 8. Prüfe Ninja-Dateien auf verbliebene x86-Flags..."

if grep -RInE \
    --include="*.ninja" \
    -- '--target=i686-linux-gnu|-m32|-malign-double|-freg-struct-return|-march=native' \
    .; then

    echo "❌ FEHLER: Verbliebene x86-Flags in Ninja-Dateien gefunden."
    exit 1
else
    echo "==> Keine bekannten x86-Flags in Ninja-Dateien gefunden."
fi

# ------------------------------------------------------------
# 12. Build-Konfiguration anzeigen
# ------------------------------------------------------------

echo "============================================================"
echo "ARM64 Build-Konfiguration"
echo "============================================================"

echo "Target:     aarch64-linux-gnu"
echo "CPU:        cortex-a35"
echo "Sysroot:    /usr/aarch64-linux-gnu"
echo "Compiler:   Clang"
echo "Linker:     LLD"
echo "============================================================"

# ------------------------------------------------------------
# 13. Build
# ------------------------------------------------------------

echo "==> 9. Baue Halo CE..."

ninja -v

# ------------------------------------------------------------
# 14. Executable suchen
# ------------------------------------------------------------

echo "==> 10. Suche kompilierte Executable..."

mkdir -p "${OUT_DIR}"

BINARY_PATH=$(
    find build \
        -type f \
        -executable \
        \( \
            -name 'halo_ce*' \
            -o \
            -name 'halo*' \
        \) \
        -print \
        | head -n 1
)

if [ -n "${BINARY_PATH}" ]; then

    echo "==> Binary gefunden:"
    echo "    ${BINARY_PATH}"

    cp "${BINARY_PATH}" \
        "${OUT_DIR}/halo_ce_rk3326"

    echo "==> Binary erfolgreich kopiert:"
    echo "    ${OUT_DIR}/halo_ce_rk3326"

    echo "==> Binary-Information:"
    file "${OUT_DIR}/halo_ce_rk3326" || true

else

    echo "❌ FEHLER: Keine kompilierte Executable gefunden."
    echo "==> Inhalt von build/:"

    find build -maxdepth 4 -type f -print | sort || true

    exit 1

fi

# ------------------------------------------------------------
# 15. Abschluss
# ------------------------------------------------------------

echo "============================================================"
echo "BUILD ERFOLGREICH"
echo "============================================================"
echo "Output:"
echo "  ${OUT_DIR}/halo_ce_rk3326"
echo "============================================================"
