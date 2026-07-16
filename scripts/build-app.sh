#!/bin/bash
# Monta dist/Maestro.app a partir do build SwiftPM (sem Xcode).
# Uso: scripts/build-app.sh [--install]
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product MaestroApp

APP=dist/Maestro.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/MaestroApp "$APP/Contents/MacOS/Maestro"
cp packaging/Info.plist "$APP/Contents/Info.plist"

mkdir -p "$APP/Contents/Frameworks"
cp -R .build/release/Sparkle.framework "$APP/Contents/Frameworks/"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/Maestro" 2>/dev/null || true

if [ ! -f assets/AppIcon.icns ]; then
  swift scripts/generate-icon.swift dist/AppIcon.iconset
  mkdir -p assets
  iconutil -c icns dist/AppIcon.iconset -o assets/AppIcon.icns
  rm -rf dist/AppIcon.iconset
fi
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --sign - --identifier com.kelvynkrug.maestro "$APP"

echo "OK: $APP"

if [ "${1:-}" = "--install" ]; then
  pkill -x Maestro 2>/dev/null || true
  sleep 1
  rm -rf /Applications/Maestro.app
  ditto "$APP" /Applications/Maestro.app
  open /Applications/Maestro.app || { sleep 2; open /Applications/Maestro.app; }
  echo "Instalado e aberto: /Applications/Maestro.app"
fi
