#!/usr/bin/env bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

SRC_DIR="${SRC_DIR:-/work/src}"
OUT_DIR="${OUT_DIR:-/work/out/haloce}"
REPO_DIR="${SRC_DIR}/halo-ce-universal}"

TARGET_CPU="${TARGET_CPU:-cortex-a35}"

mkdir -p "${SRC_DIR}"
mkdir -p "${OUT_DIR}"

echo "============================================================"
echo " Halo CE - ARM/RK3326 build analysis"
echo "============================================================"
echo
echo "Host:"
uname -a
echo
echo "Host architecture:"
uname -m
echo
echo "Target CPU:"
echo "${TARGET_CPU}"
echo

# ============================================================
# 1. Configure APT for ARM64 cross-development
# ============================================================

echo "============================================================"
echo "1. Installing dependencies"
echo "============================================================"

export DEBIAN_FRONTEND=noninteractive

# Enable ARM64 on the x86_64 GitHub Actions runner.
if ! dpkg --print-foreign-architectures | grep -qx 'arm64'; then
    echo "Enabling dpkg architecture: arm64"
    dpkg --add-architecture arm64
else
    echo "dpkg architecture arm64 is already enabled."
fi

echo
echo "Enabled architectures:"
dpkg --print-architecture
dpkg --print-foreign-architectures

# IMPORTANT:
# This must happen AFTER dpkg --add-architecture arm64.
apt-get update

# ============================================================
# Native build tools and cross toolchains
# ============================================================

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
    binutils \
    python3 \
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
    crossbuild-essential-armhf

# ============================================================
# ARM64 target development libraries
# ============================================================

apt-get install -y --no-install-recommends \
    libgbm-dev:arm64 \
    libegl1-mesa-dev:arm64 \
    libgles2-mesa-dev:arm64 \
    libdrm-dev:arm64 \
    libx11-dev:arm64 \
    libasound2-dev:arm64 \
    libpulse-dev:arm64

echo
echo "============================================================"
echo "Toolchain versions"
echo "============================================================"

clang --version | head -n 1
ld.lld --version | head -n 1
aarch64-linux-gnu-gcc --version | head -n 1
arm-linux-gnueabihf-gcc --version | head -n 1

# ============================================================
# 2. Repository
# ============================================================

echo
echo "============================================================"
echo "2. Repository"
echo "============================================================"

cd "${SRC_DIR}"

if [ ! -d "${REPO_DIR}/.git" ]; then
    rm -rf "${REPO_DIR}"

    git clone --depth=1 \
        https://github.com/cybersecurity/halo-ce-universal.git \
        "${REPO_DIR}"
else
    echo "Repository already exists."
fi

cd "${REPO_DIR}"

echo
echo "Git remote:"
git remote -v || true

echo
echo "Git revision:"
git rev-parse HEAD

# ============================================================
# 3. Initial configure
# ============================================================

echo
echo "============================================================"
echo "3. Initial configure"
echo "============================================================"

python3 configure.py --lto=thin || true

# ============================================================
# 4. Protect local changes from configure.py
# ============================================================

echo
echo "============================================================"
echo "4. Protecting local changes"
echo "============================================================"

if grep -q "git checkout" configure.py; then
    sed -i 's/git checkout/echo skipping git checkout/g' configure.py
    echo "Internal git checkout disabled."
else
    echo "No internal git checkout found."
fi

# ============================================================
# 5. Create architecture analyzer as a separate Python file
# ============================================================

echo
echo "============================================================"
echo "5. Creating architecture analyzer"
echo "============================================================"

ANALYZER="${OUT_DIR}/patch_haloce_arm64.py"

cat > "${ANALYZER}" <<'PYTHON'
#!/usr/bin/env python3

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(
    os.environ.get(
        "HALO_SOURCE_DIR",
        os.getcwd(),
    )
).resolve()


SOURCE_EXTENSIONS = {
    ".c",
    ".h",
    ".cc",
    ".cpp",
    ".hpp",
    ".py",
    ".ld",
}


def read_file(path: Path) -> str:
    try:
        return path.read_text(
            encoding="utf-8",
            errors="ignore",
        )
    except OSError:
        return ""


def run(command: list[str]) -> tuple[int, str]:
    try:
        result = subprocess.run(
            command,
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )

        return result.returncode, result.stdout

    except FileNotFoundError:
        return 127, ""


def search_tree(
    directories: list[str],
    pattern: str,
) -> list[Path]:

    regex = re.compile(pattern)

    result: list[Path] = []

    for directory in directories:
        base = ROOT / directory

        if not base.exists():
            continue

        for path in base.rglob("*"):

            if not path.is_file():
                continue

            if path.suffix not in SOURCE_EXTENSIONS:
                continue

            content = read_file(path)

            if regex.search(content):
                result.append(path)

    return sorted(set(result))


def print_matches(
    title: str,
    paths: list[Path],
) -> None:

    print()
    print(title)
    print("-" * len(title))

    if not paths:
        print("none")
        return

    for path in paths:
        try:
            relative = path.relative_to(ROOT)
        except ValueError:
            relative = path

        print(relative)


def test_aarch64_lp64() -> bool:

    clang = shutil.which("clang")

    if not clang:
        print("clang not found")
        return False

    source = ROOT / ".halo_aarch64_test.c"
    output = ROOT / ".halo_aarch64_test"

    source.write_text(
        """
#include <stdint.h>

_Static_assert(
    sizeof(void *) == 8,
    "Expected AArch64 LP64"
);

int main(void)
{
    return 0;
}
""",
        encoding="utf-8",
    )

    try:

        rc, text = run(
            [
                clang,
                "--target=aarch64-linux-gnu",
                "--sysroot=/usr/aarch64-linux-gnu",
                "-mcpu=cortex-a35",
                str(source),
                "-o",
                str(output),
            ]
        )

        if rc != 0:
            print(text)

        return rc == 0

    finally:

        source.unlink(missing_ok=True)
        output.unlink(missing_ok=True)


def test_aarch64_ilp32() -> bool:

    clang = shutil.which("clang")

    if not clang:
        return False

    source = ROOT / ".halo_ilp32_test.c"
    output = ROOT / ".halo_ilp32_test"

    source.write_text(
        """
#include <stdint.h>

_Static_assert(
    sizeof(void *) == 4,
    "Expected 32-bit pointers"
);

_Static_assert(
    sizeof(long) == 4,
    "Expected 32-bit long"
);

int main(void)
{
    return 0;
}
""",
        encoding="utf-8",
    )

    try:

        rc, text = run(
            [
                clang,
                "--target=aarch64-linux-gnu",
                "--sysroot=/usr/aarch64-linux-gnu",
                "-mabi=ilp32",
                "-mcpu=cortex-a35",
                str(source),
                "-o",
                str(output),
            ]
        )

        if rc != 0:
            print(text)

        return rc == 0

    finally:

        source.unlink(missing_ok=True)
        output.unlink(missing_ok=True)


def test_arm32() -> bool:

    compiler = shutil.which("arm-linux-gnueabihf-gcc")

    if not compiler:
        return False

    source = ROOT / ".halo_arm32_test.c"
    output = ROOT / ".halo_arm32_test"

    source.write_text(
        """
#include <stdint.h>

_Static_assert(
    sizeof(void *) == 4,
    "Expected 32-bit ARM pointers"
);

int main(void)
{
    return 0;
}
""",
        encoding="utf-8",
    )

    try:

        rc, text = run(
            [
                compiler,
                "-mcpu=cortex-a35",
                "-marm",
                str(source),
                "-o",
                str(output),
            ]
        )

        if rc != 0:
            print(text)

        return rc == 0

    finally:

        source.unlink(missing_ok=True)
        output.unlink(missing_ok=True)


def analyze() -> dict[str, bool]:

    print("=" * 64)
    print("Halo CE architecture analyzer")
    print("=" * 64)

    linux_guard_paths = search_tree(
        [
            "port",
            "source",
            "include",
        ],
        r"the Linux port targets 32-bit x86",
    )

    layout_assert_paths = search_tree(
        [
            "source",
        ],
        r"(sizeof\s*\(\s*struct|offsetof\s*\(\s*struct)",
    )

    android_ilp32_paths = search_tree(
        [
            "port/android",
            "guest",
            "host",
            "tools",
        ],
        r"\bILP32\b",
    )

    arm64_32_paths = search_tree(
        [
            "port/android",
            "guest",
            "host",
            "tools",
        ],
        r"\barm64_32\b",
    )

    linux_guard = bool(linux_guard_paths)
    layout_asserts = bool(layout_assert_paths)
    android_ilp32 = bool(android_ilp32_paths)
    arm64_32 = bool(arm64_32_paths)

    print()
    print("SOURCE ANALYSIS")
    print("---------------")

    print(
        "Linux 32-bit x86 guard :",
        linux_guard,
    )

    print(
        "Layout assertions      :",
        layout_asserts,
    )

    print(
        "Android ILP32          :",
        android_ilp32,
    )

    print(
        "arm64_32 references   :",
        arm64_32,
    )

    print_matches(
        "Linux 32-bit x86 guard locations",
        linux_guard_paths,
    )

    print_matches(
        "Layout assertion locations",
        layout_assert_paths,
    )

    print_matches(
        "Android ILP32 locations",
        android_ilp32_paths,
    )

    print_matches(
        "arm64_32 locations",
        arm64_32_paths,
    )

    print()
    print("ABI TESTS")
    print("---------")

    lp64 = test_aarch64_lp64()

    print(
        "AArch64 Linux LP64     :",
        "YES" if lp64 else "NO",
    )

    ilp32 = test_aarch64_ilp32()

    print(
        "AArch64 ILP32 compiler :",
        "YES" if ilp32 else "NO",
    )

    arm32 = test_arm32()

    print(
        "ARM32 Linux compiler   :",
        "YES" if arm32 else "NO",
    )

    print()
    print("DECISION")
    print("--------")

    if linux_guard and layout_asserts:

        print()
        print(
            "The upstream Linux port requires a "
            "32-bit game-data ABI."
        )

        print(
            "Normal AArch64 Linux uses LP64 and therefore "
            "has 64-bit pointers."
        )

        print(
            "Consequently, replacing i686 with "
            "aarch64-linux-gnu is NOT ABI compatible."
        )

        if android_ilp32 or arm64_32:

            print()
            print(
                "The source tree contains an Android "
                "ILP32/arm64_32 implementation."
            )

            print(
                "This is the relevant reference for a "
                "future native ARM64 Linux port."
            )

        print()
        print("The analyzer will NOT:")

        print(
            "  * remove sizeof/offsetof assertions"
        )

        print(
            "  * change structure sizes"
        )

        print(
            "  * convert pointers to uint32_t"
        )

        print(
            "  * force LP64 to pretend to be ILP32"
        )

    return {
        "linux_guard": linux_guard,
        "layout_asserts": layout_asserts,
        "android_ilp32": android_ilp32,
        "arm64_32": arm64_32,
        "aarch64_lp64": lp64,
        "aarch64_ilp32": ilp32,
        "arm32": arm32,
    }


def main() -> int:

    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--analyze-only",
        action="store_true",
    )

    args = parser.parse_args()

    result = analyze()

    if (
        result["linux_guard"]
        and result["layout_asserts"]
    ):

        print()
        print("=" * 64)
        print("ABI INCOMPATIBILITY DETECTED")
        print("=" * 64)

        print()
        print(
            "A normal AArch64 Linux LP64 build is unsafe."
        )

        print()
        print(
            "The build must not continue with "
            "the current Linux port."
        )

        print()
        print(
            "The source tree's Android port contains "
            "the relevant ILP32/arm64_32 architecture."
        )

        print()
        return 42

    return 0


if __name__ == "__main__":
    sys.exit(main())
PYTHON

chmod +x "${ANALYZER}"

echo "Analyzer created:"
echo "${ANALYZER}"

# ============================================================
# 6. Sanity checks
# ============================================================

echo
echo "============================================================"
echo "6. Sanity checks"
echo "============================================================"

# Make sure Python analyzer content did not accidentally
# get inserted into this Bash script.
if grep -q \
    "Halo CE architecture analyzer / safe ARM patcher" \
    "${BASH_SOURCE[0]}"; then

    echo "ERROR: Python analyzer text was found inside build.sh."
    exit 1
fi

# Validate Bash syntax before doing any build work.
bash -n "${BASH_SOURCE[0]}"

# Validate Python syntax.
python3 -m py_compile "${ANALYZER}"

rm -f "${ANALYZER}c"

echo "Bash syntax: OK"
echo "Python syntax: OK"

# ============================================================
# 7. Run architecture analyzer
# ============================================================

echo
echo "============================================================"
echo "7. Architecture analysis"
echo "============================================================"

export HALO_SOURCE_DIR="${REPO_DIR}"

set +e

python3 "${ANALYZER}" \
    --analyze-only \
    2>&1 | tee "${OUT_DIR}/architecture-analysis.txt"

ANALYZER_STATUS="${PIPESTATUS[0]}"

set -e

echo
echo "Analyzer exit code: ${ANALYZER_STATUS}"

# ============================================================
# 8. Stop on known ABI incompatibility
# ============================================================

if [ "${ANALYZER_STATUS}" -eq 42 ]; then

    echo
    echo "============================================================"
    echo "STOPPING BEFORE INVALID AArch64 BUILD"
    echo "============================================================"

    echo
    echo "The analyzer detected:"
    echo
    echo "  Linux 32-bit game-data ABI"
    echo "                 vs."
    echo "  AArch64 Linux LP64"
    echo
    echo "These ABIs are not layout-compatible."
    echo
    echo "The Android ILP32/arm64_32 implementation is the"
    echo "relevant reference for a real ARM64 Linux port."
    echo
    echo "No sizeof()/offsetof() assertions were disabled."
    echo "No game-data structures were modified."
    echo "No fake 32-bit pointer conversions were inserted."
    echo
    echo "Architecture analysis:"
    echo "${OUT_DIR}/architecture-analysis.txt"
    echo

    exit 42
fi

if [ "${ANALYZER_STATUS}" -ne 0 ]; then

    echo
    echo "ERROR: architecture analyzer failed."

    exit "${ANALYZER_STATUS}"
fi

# ============================================================
# 9. Generate build files
# ============================================================

echo
echo "============================================================"
echo "9. Generating Ninja build files"
echo "============================================================"

python3 configure.py --lto=thin

mapfile -t NINJA_FILES < <(
    find . \
        -type f \
        -name '*.ninja' \
        -print \
        | sort
)

if [ "${#NINJA_FILES[@]}" -eq 0 ]; then

    echo "ERROR: No Ninja files found."

    exit 1
fi

echo
echo "Ninja files found:"

printf '%s\n' "${NINJA_FILES[@]}"

# ============================================================
# 10. Safe compiler flag patching
# ============================================================

echo
echo "============================================================"
echo "10. Patching ARM64 compiler flags"
echo "============================================================"

for ninja_file in "${NINJA_FILES[@]}"; do

    echo "Patching:"
    echo "  ${ninja_file}"

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

done

# ============================================================
# 11. Verify forbidden x86 flags are gone
# ============================================================

echo
echo "============================================================"
echo "11. Verifying compiler flags"
echo "============================================================"

if grep -RInE \
    --include='*.ninja' \
    -- \
    '--target=i686-linux-gnu|-m32|-malign-double|-freg-struct-return|-march=native' \
    .; then

    echo
    echo "ERROR: Forbidden x86 flags remain."

    exit 1
fi

echo "No forbidden x86 compiler flags found."

# ============================================================
# 12. Build
# ============================================================

echo
echo "============================================================"
echo "12. Building"
echo "============================================================"

ninja -v

# ============================================================
# 13. Find resulting executable
# ============================================================

echo
echo "============================================================"
echo "13. Finding executable"
echo "============================================================"

mapfile -t BINARIES < <(
    find build \
        -type f \
        \( \
            -name 'halo' \
            -o -name 'halo_ce*' \
            -o -name 'halo*' \
        \) \
        -perm -111 \
        -print \
        | sort
)

if [ "${#BINARIES[@]}" -eq 0 ]; then

    echo "ERROR: No executable found."

    echo
    echo "Build tree:"
    find build \
        -maxdepth 5 \
        -type f \
        -print \
        | sort

    exit 1
fi

BINARY_PATH="${BINARIES[0]}"

# ============================================================
# 14. Verify executable architecture
# ============================================================

echo
echo "============================================================"
echo "14. Verifying executable"
echo "============================================================"

echo "Binary:"
echo "${BINARY_PATH}"

echo
echo "file:"
file "${BINARY_PATH}" || true

echo
echo "ELF header:"
readelf -h "${BINARY_PATH}" \
    | grep -E \
        'Class:|Machine:|OS/ABI:' \
    || true

# ============================================================
# 15. Copy final artifact
# ============================================================

echo
echo "============================================================"
echo "15. Copying final artifact"
echo "============================================================"

cp \
    "${BINARY_PATH}" \
    "${OUT_DIR}/halo_ce_rk3326"

echo
echo "============================================================"
echo "BUILD SUCCESSFUL"
echo "============================================================"

echo
echo "Output:"
echo "${OUT_DIR}/halo_ce_rk3326"

echo
echo "Final file:"
file "${OUT_DIR}/halo_ce_rk3326" || true
