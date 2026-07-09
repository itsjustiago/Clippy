#!/bin/bash
# Empacota a app: Clippy.dmg (instalação a arrastar) + Clippy.zip (para o auto-update).
set -euo pipefail
cd "$(dirname "$0")"

[ -d "Clippy.app" ] || { echo "Clippy.app não existe — corre ./build.sh primeiro."; exit 1; }

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

cp -R "Clippy.app" "$STAGING/Clippy.app"
ln -s /Applications "$STAGING/Applications"

rm -f Clippy.dmg
hdiutil create -volname "Clippy" -srcfolder "$STAGING" -ov -format UDZO -quiet Clippy.dmg

# Zip usado pelo atualizador embutido ( dito preserva o bundle + assinatura).
rm -f Clippy.zip
ditto -c -k --keepParent "Clippy.app" Clippy.zip

echo "✓ Clippy.dmg + Clippy.zip criados"
