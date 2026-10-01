#!/bin/bash
# Startskript für Halo CE (halo-ce-universal) auf M9 Pro / RK3326

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LD_LIBRARY_PATH="$DIR:$LD_LIBRARY_PATH"

# Panfrost Umgebungsvariablen, um OpenGL ES 3.0 Kompatibilität zu forcieren
export PAN_MESA_DEBUG=gofaster
export MESA_GLES_VERSION_OVERRIDE=3.0
export MESA_GL_VERSION_OVERRIDE=3.3

# Wechsle ins Spielverzeichnis. Die originalen Xbox-Map-Daten ("maps/") 
# müssen laut Dokumentation direkt neben der Executable liegen.
cd "$DIR"

# GPTK Steuerung starten
if [ -f "/usr/local/bin/gptokeyb" ]; then
    /usr/local/bin/gptokeyb "halo_ce_rk3326" -c "$DIR/haloce.gptk" &
fi

# Spiel starten
./halo_ce_rk3326

# GPTK beenden
if [ -f "/usr/local/bin/gptokeyb" ]; then
    killall gptokeyb
fi
