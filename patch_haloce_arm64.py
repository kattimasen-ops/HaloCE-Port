import os
import re

target_file = "configure.py"

if os.path.exists(target_file):
    with open(target_file, "r", encoding="utf-8") as f:
        content = f.read()

    # 1. Injiziere ein neues Target für Linux ARM64 (RK3326), welches den Gast-Code von Android nutzt.
    # Der Android Build nutzt musl libc für eine neue arm64_32 Architektur, um die 32-bit Limitierungen zu umgehen.
    custom_target = """
def target_linux_arm64(env):
    # Nutze das SDL3 und GLES3 Backend von Android/Linux
    env.append(CPPFLAGS=['-D_LINUX', '-DGLES3_SUPPORT'])
    # Zwinge Clang in den 32-bit Pointer Modus auf AArch64
    env.append(CCFLAGS=['-target', 'arm64_32-linux-musleabi', '-march=armv8-a', '-mabi=ilp32'])
    env.append(LDFLAGS=['-fuse-ld=lld', '-Wl,-m,aarch64elf32'])
"""
    if "def target_linux_arm64" not in content:
        content = content.replace("def target_android", custom_target + "\ndef target_android")
        print("[PATCHED] configure.py: Linux ARM64 (ILP32) Target hinzugefügt.")
    
    # 2. Deaktiviere Bink-Video strikt, da es ohnehin nicht verfügbar ist (überspringt Videos).
    content = content.replace("ENABLE_BINK = True", "ENABLE_BINK = False")

    with open(target_file, "w", encoding="utf-8") as f:
        f.write(content)
else:
    print(f"[FEHLER] {target_file} nicht gefunden.")
