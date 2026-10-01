#!/usr/bin/env python3

"""
Halo CE architecture analyzer / safe ARM patcher.

IMPORTANT:

The Halo game data uses 32-bit pointers.

The upstream Linux port is a 32-bit x86 port.

A normal AArch64 Linux process uses LP64:
    sizeof(void*) == 8

Therefore replacing i686 with aarch64-linux-gnu is NOT sufficient.

This script:

  * detects the project's ABI requirements
  * detects Android ILP32 support
  * detects 32-bit structure assertions
  * tests available Clang targets
  * tests AArch64 ILP32 compiler support
  * tests ARM32 Linux support
  * refuses unsafe structure rewriting
  * can patch only safe, known compiler flags
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent


def run(
    command: list[str],
    *,
    check: bool = False,
) -> tuple[int, str]:

    try:

        result = subprocess.run(
            command,
            cwd=ROOT,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            check=False,
        )

        if check and result.returncode != 0:
            raise RuntimeError(
                f"Command failed: {' '.join(command)}\n"
                f"{result.stdout}"
            )

        return result.returncode, result.stdout

    except FileNotFoundError:

        return 127, ""


def read_text(path: Path) -> str:

    try:

        return path.read_text(
            encoding="utf-8",
            errors="ignore",
        )

    except OSError:

        return ""


def grep_tree(
    directories: list[str],
    pattern: str,
) -> list[Path]:

    regex = re.compile(pattern)

    matches: list[Path] = []

    for directory in directories:

        root = ROOT / directory

        if not root.exists():
            continue

        for path in root.rglob("*"):

            if not path.is_file():
                continue

            if path.suffix not in {
                ".c",
                ".h",
                ".cpp",
                ".hpp",
                ".py",
                ".ld",
            }:
                continue

            content = read_text(path)

            if regex.search(content):
                matches.append(path)

    return matches


def detect_project() -> dict[str, bool]:

    linux_guard = bool(
        grep_tree(
            ["port", "source", "include"],
            r"the Linux port targets 32-bit x86",
        )
    )

    size_asserts = bool(
        grep_tree(
            ["source"],
            r"(sizeof\s*\(\s*struct|offsetof\s*\(\s*struct)",
        )
    )

    android_ilp32 = bool(
        grep_tree(
            ["port/android", "guest", "host", "tools"],
            r"\bILP32\b",
        )
    )

    arm64_32 = bool(
        grep_tree(
            ["port/android", "guest", "host", "tools"],
            r"arm64_32",
        )
    )

    return {
        "linux_guard": linux_guard,
        "size_asserts": size_asserts,
        "android_ilp32": android_ilp32,
        "arm64_32": arm64_32,
    }


def clang_target_help() -> str:

    clang = shutil.which("clang")

    if clang is None:
        return ""

    _, output = run(
        [
            clang,
            "--print-targets",
        ]
    )

    return output


def test_aarch64_lp64() -> bool:

    clang = shutil.which("clang")

    if clang is None:
        return False

    source = ROOT / ".arm64_abi_test.c"

    source.write_text(
        r"""
#include <stdint.h>
#include <stddef.h>

struct test_struct {
    void *ptr;
    uint32_t value;
};

_Static_assert(sizeof(void *) == 8, "not LP64");
_Static_assert(sizeof(struct test_struct) >= 8, "invalid ABI");

int main(void)
{
    return 0;
}
""",
        encoding="utf-8",
    )

    output = ROOT / ".arm64_abi_test"

    try:

        returncode, _ = run(
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

        return returncode == 0

    finally:

        try:
            source.unlink()
        except OSError:
            pass

        try:
            output.unlink()
        except OSError:
            pass


def test_aarch64_ilp32() -> bool:

    clang = shutil.which("clang")

    if clang is None:
        return False

    source = ROOT / ".arm64_ilp32_test.c"

    source.write_text(
        r"""
#include <stdint.h>
#include <stddef.h>

_Static_assert(sizeof(void *) == 4,
               "AArch64 ILP32 is not active");

_Static_assert(sizeof(long) == 4,
               "long is not 32 bit");

int main(void)
{
    return 0;
}
""",
        encoding="utf-8",
    )

    output = ROOT / ".arm64_ilp32_test"

    try:

        returncode, text = run(
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

        print(text)

        return returncode == 0

    finally:

        try:
            source.unlink()
        except OSError:
            pass

        try:
            output.unlink()
        except OSError:
            pass


def test_arm32_linux() -> bool:

    compiler = shutil.which("arm-linux-gnueabihf-gcc")

    if compiler is None:
        return False

    source = ROOT / ".arm32_abi_test.c"

    source.write_text(
        r"""
#include <stdint.h>

_Static_assert(sizeof(void *) == 4,
               "ARM32 must have 32-bit pointers");

int main(void)
{
    return 0;
}
""",
        encoding="utf-8",
    )

    output = ROOT / ".arm32_abi_test"

    try:

        returncode, text = run(
            [
                compiler,
                "-mcpu=cortex-a35",
                "-marm",
                str(source),
                "-o",
                str(output),
            ]
        )

        print(text)

        return returncode == 0

    finally:

        try:
            source.unlink()
        except OSError:
            pass

        try:
            output.unlink()
        except OSError:
            pass


def find_assertions() -> list[Path]:

    paths = grep_tree(
        ["source"],
        r"(size_assert|offset_assert|sizeof\s*\(\s*struct|offsetof\s*\(\s*struct)",
    )

    return sorted(set(paths))


def find_android_architecture_files() -> list[Path]:

    result: list[Path] = []

    for directory in (
        "port/android",
        "guest",
        "host",
        "tools",
    ):

        root = ROOT / directory

        if not root.exists():
            continue

        for path in root.rglob("*"):

            if not path.is_file():
                continue

            content = read_text(path)

            if (
                "ILP32" in content
                or "arm64_32" in content
                or "android_abi" in path.name
            ):
                result.append(path)

    return sorted(set(result))


def print_report() -> dict[str, bool]:

    print("=" * 60)
    print("Halo CE ARM architecture analysis")
    print("=" * 60)

    project = detect_project()

    print()
    print("Project characteristics:")
    print(
        "  Linux 32-bit x86 guard: ",
        project["linux_guard"],
    )
    print(
        "  Structure layout asserts:",
        project["size_asserts"],
    )
    print(
        "  Android ILP32 code:      ",
        project["android_ilp32"],
    )
    print(
        "  arm64_32 support:        ",
        project["arm64_32"],
    )

    print()
    print("Compiler:")
    print(
        "  clang:",
        shutil.which("clang") or "NOT FOUND",
    )
    print(
        "  aarch64-linux-gnu-gcc:",
        shutil.which("aarch64-linux-gnu-gcc") or "NOT FOUND",
    )
    print(
        "  arm-linux-gnueabihf-gcc:",
        shutil.which("arm-linux-gnueabihf-gcc") or "NOT FOUND",
    )

    print()
    print("Clang target information:")

    targets = clang_target_help()

    if targets:
        for line in targets.splitlines():
            if "aarch64" in line.lower():
                print(" ", line)

    print()
    print("ABI tests:")

    lp64 = test_aarch64_lp64()
    print(
        "  AArch64 Linux LP64:",
        "YES" if lp64 else "NO",
    )

    ilp32 = test_aarch64_ilp32()
    print(
        "  AArch64 ILP32 compiler:",
        "YES" if ilp32 else "NO",
    )

    arm32 = test_arm32_linux()
    print(
        "  ARM32 Linux compiler:",
        "YES" if arm32 else "NO",
    )

    print()
    print("Structure assertions:")

    assertions = find_assertions()

    print(
        f"  {len(assertions)} source files contain "
        "layout checks."
    )

    for path in assertions[:50]:
        print("   ", path.relative_to(ROOT))

    print()
    print("Android ILP32 implementation:")

    android_files = find_android_architecture_files()

    for path in android_files[:100]:
        print("   ", path.relative_to(ROOT))

    print()
    print("=" * 60)
    print("Architecture conclusion")
    print("=" * 60)

    if project["linux_guard"] and project["size_asserts"]:

        print()
        print(
            "The upstream Linux port requires a 32-bit "
            "data model."
        )

        print()
        print(
            "Normal AArch64 Linux is LP64 and therefore "
            "uses 64-bit pointers."
        )

        print()
        print(
            "The Android port solves this using an "
            "ILP32 AArch64 guest."
        )

        if ilp32:

            print()
            print(
                "Clang accepts -mabi=ilp32, but this does "
                "NOT mean a normal Ubuntu Linux executable "
                "can be linked and executed."
            )

        print()
        print(
            "The safe options are:"
        )

        print(
            "  1. Port the Android guest/host architecture "
            "to Linux AArch64."
        )

        print(
            "  2. Build the existing 32-bit game for "
            "AArch32/ARM Linux."
        )

        print()
        print(
            "The script will NOT modify structure definitions "
            "or disable layout assertions."
        )

    return {
        **project,
        "aarch64_lp64": lp64,
        "aarch64_ilp32": ilp32,
        "arm32": arm32,
    }


def patch_safe_flags() -> None:

    configure = ROOT / "configure.py"

    if not configure.exists():
        print(
            "[ERROR] configure.py not found.",
            file=sys.stderr,
        )
        sys.exit(1)

    content = read_text(configure)

    original = content

    replacements = [
        (
            r"--target=i686-linux-gnu",
            "--target=aarch64-linux-gnu "
            "--sysroot=/usr/aarch64-linux-gnu",
        ),
        (
            r"-m32",
            "",
        ),
        (
            r"-malign-double",
            "",
        ),
        (
            r"-freg-struct-return",
            "",
        ),
        (
            r"-march=native",
            "-mcpu=cortex-a35",
        ),
    ]

    for pattern, replacement in replacements:

        content = re.sub(
            pattern,
            replacement,
            content,
        )

    if content != original:

        configure.write_text(
            content,
            encoding="utf-8",
        )

        print(
            "[PATCHED] configure.py"
        )

    forbidden = [
        r"--target=i686-linux-gnu",
        r"-m32",
        r"-malign-double",
        r"-freg-struct-return",
        r"-march=native",
    ]

    remaining = [
        pattern
        for pattern in forbidden
        if re.search(pattern, content)
    ]

    if remaining:

        print(
            "[ERROR] Unsafe x86 flags remain:"
        )

        for item in remaining:
            print(
                " ",
                item,
            )

        sys.exit(1)


def main() -> None:

    parser = argparse.ArgumentParser()

    parser.add_argument(
        "--analyze-only",
        action="store_true",
        help="Only analyze the repository.",
    )

    parser.add_argument(
        "--patch",
        action="store_true",
        help="Apply safe compiler-flag patches.",
    )

    args = parser.parse_args()

    result = print_report()

    if args.analyze_only:
        return

    if args.patch:

        if (
            result["linux_guard"]
            and result["size_asserts"]
        ):

            print()
            print(
                "[SAFE MODE] The project requires ILP32."
            )

            print(
                "No structure rewriting will be performed."
            )

            print(
                "Only compiler flag cleanup is allowed."
            )

        patch_safe_flags()

        print()
        print(
            "[OK] Safe compiler flag patching complete."
        )

    else:

        print()
        print(
            "No source modifications requested."
        )


if __name__ == "__main__":
    main()
