#!/usr/bin/env python3

import os
import re
import sys


def patch_file(filepath, replacements):
    """
    Apply a list of regex replacements to a file.
    """

    if not os.path.exists(filepath):
        print(f"[SKIP] Datei nicht gefunden: {filepath}")
        return False

    with open(
        filepath,
        "r",
        encoding="utf-8",
        errors="ignore",
    ) as f:
        content = f.read()

    modified = content

    for pattern, replacement in replacements:
        modified = re.sub(
            pattern,
            replacement,
            modified,
        )

    if modified != content:

        with open(
            filepath,
            "w",
            encoding="utf-8",
        ) as f:
            f.write(modified)

        print(f"[PATCHED] {filepath}")
        return True

    print(f"[NO CHANGE] {filepath}")
    return False


def verify_configure_py(filepath):
    """
    Make sure known x86-specific options are gone.
    """

    if not os.path.exists(filepath):
        print(f"[ERROR] {filepath} nicht gefunden.")
        return False

    with open(
        filepath,
        "r",
        encoding="utf-8",
        errors="ignore",
    ) as f:
        content = f.read()

    forbidden = [
        r"--target=i686-linux-gnu",
        r"-m32",
        r"-malign-double",
        r"-freg-struct-return",
        r"-march=native",
    ]

    found = []

    for pattern in forbidden:
        if re.search(pattern, content):
            found.append(pattern)

    if found:
        print(
            "[ERROR] Folgende x86-Optionen wurden in "
            "configure.py noch gefunden:"
        )

        for item in found:
            print(f"    {item}")

        return False

    print(
        "[OK] configure.py enthält keine bekannten "
        "x86-spezifischen Optionen mehr."
    )

    return True


def main():

    print("============================================================")
    print("Halo CE ARM64 / RK3326 Patch-Prozess")
    print("============================================================")

    configure_py = "configure.py"

    # --------------------------------------------------------
    # ARM64 Cross-Compilation
    # --------------------------------------------------------

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

    print("==> Patche configure.py...")

    patch_file(
        configure_py,
        replacements,
    )

    # --------------------------------------------------------
    # Verification
    # --------------------------------------------------------

    print("==> Prüfe configure.py...")

    if not verify_configure_py(configure_py):
        print(
            "❌ ARM64-Patch konnte nicht erfolgreich "
            "verifiziert werden."
        )
        sys.exit(1)

    # --------------------------------------------------------
    # Abschluss
    # --------------------------------------------------------

    print("============================================================")
    print("ARM64 / RK3326 Patch erfolgreich abgeschlossen.")
    print("Target: aarch64-linux-gnu")
    print("CPU:    cortex-a35")
    print("Sysroot: /usr/aarch64-linux-gnu")
    print("============================================================")


if __name__ == "__main__":
    main()
