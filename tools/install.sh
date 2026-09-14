#!/usr/bin/env bash
# install.sh — bootstrap installer DZR Integrity (jalankan DI VPS)
#
# Pakai:
#   bash install.sh            -> pasang modul + laporan deteksi (tanpa perubahan)
#   bash install.sh --auto     -> pasang modul + hook otomatis (dengan backup) + restart bot
#
# One-liner (dari luar):
#   curl -fsSL https://raw.githubusercontent.com/hecker123452-coder/apk-builder/main/tools/install.sh | bash -s -- --auto
set -u
RAW="https://raw.githubusercontent.com/hecker123452-coder/apk-builder/main/tools"
DEST="/opt/dzr"

fetch() { # fetch <url> <out>
  if command -v curl >/dev/null 2>&1; then curl -fsSL "$1" -o "$2"; else wget -qO "$2" "$1"; fi
}

echo "[1/2] Download modul + installer -> $DEST"
mkdir -p "$DEST"
fetch "$RAW/dzr-integrity.js" "$DEST/dzr-integrity.js" || { echo "GAGAL: download dzr-integrity.js"; exit 1; }
fetch "$RAW/dzr-install.js"   "$DEST/dzr-install.js"   || { echo "GAGAL: download dzr-install.js"; exit 1; }
echo "  OK"

echo "[2/2] Deteksi bot DZR..."
exec node "$DEST/dzr-install.js" "$@"
