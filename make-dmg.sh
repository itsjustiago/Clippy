#!/bin/bash
# Cria um Clippy.dmg com a app + atalho para Aplicações (instalação a arrastar).
set -euo pipefail
cd "$(dirname "$0")"

[ -d "Clippy.app" ] || { echo "Clippy.app não existe — corre ./build.sh primeiro."; exit 1; }

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "Clippy.app" "$STAGING/Clippy.app"
ln -s /Applications "$STAGING/Applications"

rm -f Clippy.dmg
hdiutil create -volname "Clippy" -srcfolder "$STAGING" -ov -format UDZO -quiet Clippy.dmg

echo "✓ Clippy.dmg criado"
