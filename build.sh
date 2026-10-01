#!/bin/bash
# ============================================================
# Halo CE Universal - ARM Cross Build / Architecture Analyzer
#
# Host:
#   Ubuntu 24.04 x86_64
#
# Target hardware:
#   Rockchip RK3326 / Cortex-A35
#
# IMPORTANT:
#   The upstream Linux port is 32-bit x86.
#   The Android port uses an ILP32 AArch64 guest because the
#   Halo/Xbox data structures contain 32-bit pointers.
#
# This script therefore DOES NOT blindly replace i686 with
# aarch64-linux-gnu.
#
# It analyzes the project first and selects the only ABI which
# can actually represent the required 32-bit data layout.
# ============================================================

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

SRC_DIR="${SRC_DIR:-/work/src}"
OUT_DIR="${OUT_DIR:-/work/out/haloce}"
REPO_DIR="${SRC_DIR}/halo-ce-universal"

TARGET_CPU="${TARGET_CPU:-cortex-a35}"

mkdir -p "${SRC_DIR}"
mkdir -p "${OUT_DIR}"

echo
echo "============================================================"
echo " Halo CE - ARM Architecture Analysis"
echo "============================================================"
echo

echo "Host:"
uname -a
echo
echo "Host architecture:"
uname -m
echo

# ------------------------------------------------------------
# 1. Dependencies
# ------------------------------------------------------------

echo "============================================================"
echo "1. Installing build dependencies"
echo "============================================================"

apt-get update

apt-get install -y --no-install-recommends \
    build-essential \
    git \
    pkg-config \
    ca-certificates \
    wget \
    curl \
    unzip \
    zip \
    file \
    python3 \
    python3-pip \
    ninja-build \
    clang \
    lld \
    llvm \
    cmake \
    gcc-aarch64-linux-gnu \
    g++-aarch64-linux-gnu \
    gcc-arm-linux-gnueabihf \
    g++-arm-linux-gnueabihf \
    binutils-aarch64-linux-gnu \
    binutils-arm-linux-gnueabihf \
    crossbuild-essential-arm64 \
    crossbuild-essential-armhf \
    libgbm-dev:arm64 \
    libegl1-mesa-dev:arm64 \
    libgles2-mesa-dev:arm64 \
    libdrm-dev:arm64 \
    libx11-dev:arm64 \
    libasound2-dev:arm64 \
    libpulse-dev:arm64

echo
echo "Compiler versions:"
clang --version | head -n 1
ld.lld --version | head -n 1
aarch64-linux-gnu-gcc --version | head -n 1
arm-linux-gnueabihf-gcc --version | head -n 1
echo

# ------------------------------------------------------------
# 2. Repository
# ------------------------------------------------------------

echo "============================================================"
echo "2. Repository"
echo "============================================================"

cd "${SRC_DIR}"

if [ ! -d "${REPO_DIR}/.git" ]; then

    echo "==> Cloning repository..."

    rm -rf "${REPO_DIR}"

    git clone \
        --depth=1 \
        https://github.com/cybersecurity/halo-ce-universal.git \
        "${REPO_DIR}"

else

    echo "==> Repository already exists."

fi

cd "${REPO_DIR}"

echo
echo "Repository:"
git remote -v || true
echo
echo "Commit:"
git rev-parse HEAD
echo

# ------------------------------------------------------------
# 3. First configure
#
# The upstream configure script downloads dependencies and may
# perform an internal checkout. Allow that ONCE.
# ------------------------------------------------------------

echo "============================================================"
echo "3. Initial configure / dependency bootstrap"
echo "============================================================"

python3 configure.py --lto=thin || true

# ------------------------------------------------------------
# 4. Disable internal checkout
# ------------------------------------------------------------

echo "============================================================"
echo "4. Protect local architecture changes"
echo "============================================================"

if grep -q "git checkout" configure.py; then

    echo "==> Disabling configure.py internal git checkout."

    sed -i \
        's/git checkout/echo skipping git checkout/g' \
        configure.py

else

    echo "==> No internal git checkout found."

fi

# ------------------------------------------------------------
# 5. Optional external patch script
# ------------------------------------------------------------

if [ -f "/work/patch_haloce_arm64.py" ]; then

    echo
    echo "============================================================"
    echo "5. Running architecture analyzer / patcher"
    echo "============================================================"

    python3 /work/patch_haloce_arm64.py

fi

# ------------------------------------------------------------
# 6. Repository architecture analysis
# ------------------------------------------------------------

echo
echo "============================================================"
echo "6. Analyze project architecture"
echo "============================================================"

ANALYSIS_LOG="${OUT_DIR}/architecture-analysis.txt"

python3 /work/patch_haloce_arm64.py \
    --analyze-only \
    2>&1 | tee "${ANALYSIS_LOG}" || true

# ------------------------------------------------------------
# 7. Detect project requirements
# ------------------------------------------------------------

echo
echo "============================================================"
echo "7. Detect Halo ABI requirements"
echo "============================================================"

HAS_32BIT_GUARD=0
HAS_SIZE_ASSERTS=0
HAS_ANDROID_ILP32=0
HAS_ARM64_32=0

if grep -Rqs \
    "the Linux port targets 32-bit x86" \
    port source include 2>/dev/null; then

    HAS_32BIT_GUARD=1

fi

if grep -RqsE \
    "sizeof\(struct .*== 0x|offsetof\(struct .*== 0x" \
    source 2>/dev/null; then

    HAS_SIZE_ASSERTS=1

fi

if grep -Rqs \
    "arm64_32" \
    port/android tools guest 2>/dev/null; then

    HAS_ARM64_32=1

fi

if grep -Rqs \
    "ILP32" \
    port/android tools guest 2>/dev/null; then

    HAS_ANDROID_ILP32=1

fi

echo "32-bit Linux guard:      ${HAS_32BIT_GUARD}"
echo "Structure size asserts:  ${HAS_SIZE_ASSERTS}"
echo "Android ILP32 support:  ${HAS_ANDROID_ILP32}"
echo "arm64_32 support:       ${HAS_ARM64_32}"

# ------------------------------------------------------------
# 8. Native AArch64 ABI test
# ------------------------------------------------------------

echo
echo "============================================================"
echo "8. Test native AArch64 ABI"
echo "============================================================"

cat > "${OUT_DIR}/abi_test.c" <<'EOF'
#include <stdio.h>
#include <stdint.h>
#include <stddef.h>

struct abi_test {
    void *pointer;
    uint32_t value;
};

int main(void)
{
    printf("sizeof(void*)=%zu\n", sizeof(void *));
    printf("sizeof(long)=%zu\n", sizeof(long));
    printf("sizeof(int)=%zu\n", sizeof(int));
    printf("sizeof(struct abi_test)=%zu\n", sizeof(struct abi_test));
    printf("offsetof(value)=%zu\n",
           offsetof(struct abi_test, value));

    return 0;
}
EOF

ABI_AARCH64="${OUT_DIR}/abi-aarch64"

if clang \
    --target=aarch64-linux-gnu \
    --sysroot=/usr/aarch64-linux-gnu \
    -mcpu="${TARGET_CPU}" \
    "${OUT_DIR}/abi_test.c" \
    -o "${ABI_AARCH64}"; then

    echo "==> Native AArch64 compiler test succeeded."

    file "${ABI_AARCH64}" || true

    if "${ABI_AARCH64}" >/dev/null 2>&1; then
        echo "==> AArch64 executable runs on host unexpectedly."
    else
        echo "==> Expected: ARM64 executable cannot execute on x86 host."
    fi

    echo
    echo "AArch64 ABI:"
    readelf -h "${ABI_AARCH64}" | grep -E \
        'Class:|Machine:' || true

else

    echo "WARNING: Native AArch64 compiler test failed."

fi

# ------------------------------------------------------------
# 9. Explicitly test AArch64 ILP32 compiler support
#
# We do NOT assume that -mabi=ilp32 is usable for Linux.
# The compiler may accept it while the required Linux libc/
# loader does not exist.
# ------------------------------------------------------------

echo
echo "============================================================"
echo "9. Test AArch64 ILP32 support"
echo "============================================================"

ABI_ILP32="${OUT_DIR}/abi-aarch64-ilp32"

ILP32_SUPPORTED=0

if clang \
    --target=aarch64-linux-gnu \
    --sysroot=/usr/aarch64-linux-gnu \
    -mabi=ilp32 \
    -mcpu="${TARGET_CPU}" \
    "${OUT_DIR}/abi_test.c" \
    -o "${ABI_ILP32}" \
    2>"${OUT_DIR}/ilp32-build.log"; then

    echo "==> Compiler accepted AArch64 ILP32."

    if file "${ABI_ILP32}" | grep -qi \
        "ARM aarch64"; then

        ILP32_SUPPORTED=1

    fi

else

    echo "==> Compiler/sysroot cannot build AArch64 ILP32."

fi

cat "${OUT_DIR}/ilp32-build.log" || true

echo
echo "Compiler-level AArch64 ILP32 support: ${ILP32_SUPPORTED}"

# ------------------------------------------------------------
# 10. IMPORTANT ARCHITECTURE DECISION
# ------------------------------------------------------------

echo
echo "============================================================"
echo "10. Architecture decision"
echo "============================================================"

if [ "${HAS_SIZE_ASSERTS}" -eq 1 ] && \
   [ "${HAS_32BIT_GUARD}" -eq 1 ]; then

    echo
    echo "The source explicitly requires a 32-bit data model."
    echo
    echo "A normal aarch64-linux-gnu build is LP64:"
    echo "  sizeof(void*) = 8"
    echo
    echo "The Halo data structures require 32-bit pointers."
    echo
    echo "The Android port solves this with an ILP32 guest."
    echo
    echo "Therefore:"
    echo
    echo "  aarch64-linux-gnu + normal Linux libc"
    echo "  is NOT accepted as a valid Halo guest ABI."
    echo

fi

# ------------------------------------------------------------
# 11. Do NOT disable size assertions
# ------------------------------------------------------------

echo
echo "============================================================"
echo "11. Verify structure assertions remain enabled"
echo "============================================================"

if grep -RInE \
    --include='*.h' \
    --include='*.c' \
    'size_assert|offset_assert|sizeof\(struct|offsetof\(struct' \
    source \
    > "${OUT_DIR}/structure-assertions.txt" \
    2>/dev/null; then

    echo "==> Structure assertions detected:"
    wc -l "${OUT_DIR}/structure-assertions.txt"

else

    echo "WARNING: No structure assertions detected."

fi

# ------------------------------------------------------------
# 12. Test ARM32 Linux fallback
#
# This is the important Linux-compatible fallback:
#
#   ARMv8 CPU
#       |
#       +-- AArch32 execution
#             |
#             +-- 32-bit pointers
#             +-- Linux ABI
#
# RK3326/Cortex-A35 hardware is capable of AArch32 execution,
# but the target kernel/userspace must provide 32-bit support.
#
# We only build this fallback if the user explicitly allows it.
# ------------------------------------------------------------

ALLOW_ARM32_FALLBACK="${ALLOW_ARM32_FALLBACK:-1}"

echo
echo "============================================================"
echo "12. ARM32 Linux compatibility test"
echo "============================================================"

ARM32_TEST="${OUT_DIR}/abi-arm32"

if [ "${ALLOW_ARM32_FALLBACK}" = "1" ]; then

    if arm-linux-gnueabihf-gcc \
        -mcpu="${TARGET_CPU}" \
        -marm \
        "${OUT_DIR}/abi_test.c" \
        -o "${ARM32_TEST}"; then

        echo "==> ARM32 Linux toolchain works."

        file "${ARM32_TEST}" || true

        readelf -h "${ARM32_TEST}" | grep -E \
            'Class:|Machine:' || true

    else

        echo "WARNING: ARM32 Linux compiler test failed."

    fi

else

    echo "ARM32 fallback disabled."
fi

# ------------------------------------------------------------
# 13. Decide what is actually buildable
# ------------------------------------------------------------

echo
echo "============================================================"
echo "13. Final build-mode selection"
echo "============================================================"

if [ "${ILP32_SUPPORTED}" -eq 1 ]; then

    echo
    echo "WARNING:"
    echo "Compiler accepts AArch64 ILP32, but Linux runtime support"
    echo "must still be verified. Ubuntu/glibc does not provide a"
    echo "normal supported AArch64 ILP32 userspace."
    echo
    echo "The script will NOT silently use it."
    echo

fi

# ------------------------------------------------------------
# 14. Use upstream Android architecture knowledge if needed
# ------------------------------------------------------------

echo
echo "============================================================"
echo "14. Inspect Android ILP32 implementation"
echo "============================================================"

if [ "${HAS_ARM64_32}" -eq 1 ]; then

    echo
    echo "Relevant Android ILP32 files:"
    find \
        port/android \
        guest \
        host \
        tools \
        -type f \
        \( \
            -name '*.c' \
            -o \
            -name '*.h' \
            -o \
            -name '*.py' \
            -o \
            -name '*.ld' \
        \) \
        -print \
        2>/dev/null \
        | grep -E \
            'android|guest|host|abi|ilp32' \
        | sort \
        | head -n 200 \
        || true

fi

# ------------------------------------------------------------
# 15. Build strategy
# ------------------------------------------------------------
#
# We deliberately refuse to pretend that LP64 is compatible.
#
# To produce a native ARM64 Linux binary, the Linux port itself
# needs the Android-style guest/host split:
#
#     RK3326 Linux host
#           |
#           +-- native AArch64 host library
#           |
#           +-- ILP32 AArch64 guest
#
# The upstream Android implementation already contains most of
# this architecture, but it is coupled to Android's NDK/runtime.
#
# Automatically rewriting C structs would corrupt the binary
# layout and is therefore explicitly forbidden here.
# ------------------------------------------------------------

echo
echo "============================================================"
echo "15. Build validation"
echo "============================================================"

if [ "${HAS_SIZE_ASSERTS}" -eq 1 ] && \
   [ "${HAS_32BIT_GUARD}" -eq 1 ]; then

    echo
    echo "============================================================"
    echo "STOP: Native AArch64 Linux LP64 build is ABI-incompatible"
    echo "============================================================"
    echo
    echo "Detected:"
    echo "  - Linux port requires 32-bit x86-style data layout"
    echo "  - Halo structures contain 32-bit pointers"
    echo "  - Native AArch64 Linux uses 64-bit pointers"
    echo "  - Structure size/offset assertions enforce the original ABI"
    echo
    echo "A normal:"
    echo
    echo "  --target=aarch64-linux-gnu"
    echo
    echo "build MUST NOT continue."
    echo
    echo "The upstream project already solves the same fundamental"
    echo "problem in the Android port using an ILP32 AArch64 guest."
    echo
    echo "See:"
    echo "  port/android/README.md"
    echo
    echo "For a native RK3326 Linux executable, the next required"
    echo "port is the Android guest/host architecture to Linux."
    echo
    echo "Alternatively, an ARM32 Linux build can be used if the"
    echo "RK3326 kernel/userspace provides AArch32 compatibility."
    echo
    echo "No size assertions were disabled."
    echo "No pointer types were rewritten automatically."
    echo
    echo "Architecture analysis:"
    echo "  ${ANALYSIS_LOG}"
    echo
    echo "Structure assertions:"
    echo "  ${OUT_DIR}/structure-assertions.txt"
    echo

    exit 42

fi

# ------------------------------------------------------------
# 16. If project changes in the future and no longer has the
#     32-bit Linux restriction, configure/build normally.
# ------------------------------------------------------------

echo
echo "============================================================"
echo "16. Configure"
echo "============================================================"

python3 configure.py --lto=thin

# ------------------------------------------------------------
# 17. Patch generated Ninja files only for actual compiler
#     architecture flags.
# ------------------------------------------------------------

echo
echo "============================================================"
echo "17. Analyze generated Ninja files"
echo "============================================================"

find . \
    -type f \
    -name '*.ninja' \
    -print \
    > "${OUT_DIR}/ninja-files.txt"

while IFS= read -r ninja_file; do

    echo "Checking ${ninja_file}"

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

done < "${OUT_DIR}/ninja-files.txt"

# ------------------------------------------------------------
# 18. Build
# ------------------------------------------------------------

echo
echo "============================================================"
echo "18. Ninja build"
echo "============================================================"

ninja -v

# ------------------------------------------------------------
# 19. Find executable
# ------------------------------------------------------------

echo
echo "============================================================"
echo "19. Find executable"
echo "============================================================"

mapfile -t CANDIDATES < <(
    find build \
        -type f \
        \( \
            -name 'halo' \
            -o \
            -name 'halo_ce*' \
            -o \
            -name 'halo*' \
        \) \
        -perm -111 \
        -print \
        2>/dev/null \
        | sort
)

if [ "${#CANDIDATES[@]}" -eq 0 ]; then

    echo "ERROR: No executable found."

    find build \
        -maxdepth 5 \
        -type f \
        -print \
        | sort \
        || true

    exit 1

fi

BINARY_PATH="${CANDIDATES[0]}"

echo
echo "Selected binary:"
echo "  ${BINARY_PATH}"

file "${BINARY_PATH}" || true

echo
echo "ELF architecture:"
readelf -h "${BINARY_PATH}" | grep -E \
    'Class:|Data:|Machine:|OS/ABI:' \
    || true

# ------------------------------------------------------------
# 20. Copy artifact
# ------------------------------------------------------------

cp \
    "${BINARY_PATH}" \
    "${OUT_DIR}/halo_ce_rk3326"

echo
echo "============================================================"
echo "BUILD COMPLETE"
echo "============================================================"
echo
echo "Output:"
echo "  ${OUT_DIR}/halo_ce_rk3326"
echo
echo "Architecture:"
file "${OUT_DIR}/halo_ce_rk3326" || true
echo
