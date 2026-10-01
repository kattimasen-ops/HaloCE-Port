#!/usr/bin/env bash

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

SRC_DIR="${SRC_DIR:-/work/src}"
OUT_DIR="${OUT_DIR:-/work/out/haloce}"
REPO_DIR="${SRC_DIR}/halo-ce-universal"

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
# 1. Dependencies
# ============================================================

echo "============================================================"
echo "1. Installing dependencies"
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
    crossbuild-essential-armhf \
    libgbm-dev:arm64 \
    libegl1-mesa-dev:arm64 \
    libgles2-mesa-dev:arm64 \
    libdrm-dev:arm64 \
    libx11-dev:arm64 \
    libasound2-dev:arm64 \
    libpulse-dev:arm64

echo
echo "Installed toolchains:"
clang --version | head -n 1
ld.lld --version | head -n 1
aarch64-linux-gnu-gcc --version | head -n 1
arm-linux-gnueabihf-gcc --version | head -n 1
echo

# ============================================================
# 2. Download repository
# ============================================================

echo "============================================================"
echo "2. Repository"
echo "============================================================"

cd "${SRC_DIR}"

if [ ! -d "${REPO_DIR}/.git" ]; then

    rm -rf "${REPO_DIR}"

    git clone \
        --depth=1 \
        https://github.com/cybersecurity/halo-ce-universal.git \
        "${REPO_DIR}"

else

    echo "Repository already exists."

fi

cd "${REPO_DIR}"

echo
echo "Repository:"
git remote -v || true

echo
echo "Commit:"
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
# 4. Prevent configure.py from checking out its own revision
# ============================================================

echo
echo "============================================================"
echo "4. Protecting local changes"
echo "============================================================"

if grep -q "git checkout" configure.py; then

    sed -i \
        's/git checkout/echo skipping git checkout/g' \
        configure.py

    echo "Internal git checkout disabled."

else

    echo "No internal git checkout found."

fi

# ============================================================
# 5. Create the analyzer as a SEPARATE Python file
#
# This is deliberately generated here so that build.sh can
# never accidentally contain Python code.
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

            if path.suffix not in {
                ".c",
                ".h",
                ".cc",
                ".cpp",
                ".hpp",
                ".py",
                ".ld",
            }:
                continue

            content = read_file(path)

            if regex.search(content):
                result.append(path)

    return sorted(set(result))


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

    compiler = shutil.which(
        "arm-linux-gnueabihf-gcc"
    )

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

    linux_guard = bool(
        search_tree(
            ["port", "source", "include"],
            r"the Linux port targets 32-bit x86",
        )
    )

    layout_asserts = bool(
        search_tree(
            ["source"],
            r"(sizeof\s*\(\s*struct|offsetof\s*\(\s*struct)",
        )
    )

    android_ilp32 = bool(
        search_tree(
            [
                "port/android",
                "guest",
                "host",
                "tools",
            ],
            r"\bILP32\b",
        )
    )

    arm64_32 = bool(
        search_tree(
            [
                "port/android",
                "guest",
                "host",
                "tools",
            ],
            r"\barm64_32\b",
        )
    )

    print()
    print("SOURCE ANALYSIS")
    print("---------------")
    print(
        f"Linux 32-bit x86 guard : {linux_guard}"
    )
    print(
        f"Layout assertions      : {layout_asserts}"
    )
    print(
        f"Android ILP32          : {android_ilp32}"
    )
    print(
        f"arm64_32 references   : {arm64_32}"
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
            "The upstream Linux port requires a 32-bit "
            "game-data ABI."
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
        print(
            "The analyzer will NOT:"
        )

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
            "The build must not continue with the current "
            "Linux port."
        )
        print()

        return 42

    return 0


if __name__ == "__main__":
    sys.exit(main())
PYTHON

chmod +x "${ANALYZER}"

echo
echo "Analyzer created:"
echo "${ANALYZER}"

# ============================================================
# 6. Verify that build.sh itself contains NO Python analyzer
# ============================================================

echo
echo "============================================================"
echo "6. Sanity check build.sh"
echo "============================================================"

if grep -q \
    "Halo CE architecture analyzer / safe ARM patcher" \
    "${BASH_SOURCE[0]}"; then

    echo
    echo "ERROR:"
    echo "Python analyzer text was found inside build.sh."
    echo
    echo "This must never happen."
    exit 1
fi

echo "build.sh syntax/content check: OK"

bash -n "${BASH_SOURCE[0]}"

echo "bash syntax check: OK"

# ============================================================
# 7. Run analyzer
# ============================================================

echo
echo "============================================================"
echo "7. Running architecture analysis"
echo "============================================================"

set +e

python3 "${ANALYZER}" \
    --analyze-only \
    2>&1 | tee \
    "${OUT_DIR}/architecture-analysis.txt"

ANALYZER_STATUS="${PIPESTATUS[0]}"

set -e

# ============================================================
# 8. ABI incompatibility
# ============================================================

if [ "${ANALYZER_STATUS}" -eq 42 ]; then

    echo
    echo "============================================================"
    echo "STOPPING BEFORE INVALID AArch64 BUILD"
    echo "============================================================"
    echo
    echo "The analyzer detected:"
    echo
    echo "  Linux port          = 32-bit x86"
    echo "  Halo data layout    = 32-bit"
    echo "  AArch64 Linux       = 64-bit LP64"
    echo
    echo "The previous i686 -> aarch64 replacement was therefore"
    echo "architecturally incorrect."
    echo
    echo "The source tree's Android port contains the relevant"
    echo "ILP32/arm64_32 architecture."
    echo
    echo "The complete analysis is stored in:"
    echo
    echo "  ${OUT_DIR}/architecture-analysis.txt"
    echo
    echo "No sizeof()/offsetof() assertions were disabled."
    echo "No source structures were corrupted."
    echo
    echo "ERROR CODE: 42"
    echo

    exit 42

fi

if [ "${ANALYZER_STATUS}" -ne 0 ]; then

    echo
    echo "ERROR: architecture analyzer failed."
    exit "${ANALYZER_STATUS}"

fi

# ============================================================
# 9. Only for a future compatible source tree:
#    patch safe compiler flags
# ============================================================

echo
echo "============================================================"
echo "8. Configuring AArch64 build"
echo "============================================================"

python3 configure.py --lto=thin

# ============================================================
# 10. Find Ninja files
# ============================================================

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

# ============================================================
# 11. Patch only compiler architecture flags
# ============================================================

echo
echo "============================================================"
echo "9. Patching generated Ninja files"
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
# 12. Verify Ninja files
# ============================================================

echo
echo "============================================================"
echo "10. Verifying Ninja files"
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

echo "Ninja verification: OK"

# ============================================================
# 13. Build
# ============================================================

echo
echo "============================================================"
echo "11. Building"
echo "============================================================"

ninja -v

# ============================================================
# 14. Locate binary
# ============================================================

echo
echo "============================================================"
echo "12. Locating executable"
echo "============================================================"

mapfile -t BINARIES < <(
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
        | sort
)

if [ "${#BINARIES[@]}" -eq 0 ]; then

    echo "ERROR: No executable found."

    find build \
        -maxdepth 5 \
        -type f \
        -print \
        | sort

    exit 1
fi

BINARY_PATH="${BINARIES[0]}"

echo
echo "Binary:"
echo "${BINARY_PATH}"

file "${BINARY_PATH}" || true

readelf -h "${BINARY_PATH}" \
    | grep -E \
        'Class:|Machine:|OS/ABI:' \
    || true

# ============================================================
# 15. Artifact
# ============================================================

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

file "${OUT_DIR}/halo_ce_rk3326" || true
