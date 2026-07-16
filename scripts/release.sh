#!/bin/bash
# Release local completa: build → assinatura Developer ID (hardened runtime)
# → notarização → staple → appcast do Sparkle → GitHub Release → cask no tap.
#
# Pré-requisitos (uma vez):
#   1. Certificado "Developer ID Application" no Keychain.
#   2. xcrun notarytool store-credentials maestro-notary \
#        --apple-id SEU@EMAIL --team-id SEUTEAMID --password SENHA-DE-APP
#   3. Chave EdDSA do Sparkle no Keychain (gerada com generate_keys).
#   4. gh CLI autenticado na conta kelvynkrug.
#
# A cada release: bump em CFBundleShortVersionString no packaging/Info.plist
# e rodar scripts/release.sh. Depois, commitar o bump do Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' packaging/Info.plist)
IDENTITY="${MAESTRO_SIGN_IDENTITY:-Developer ID Application}"
PROFILE="${MAESTRO_NOTARY_PROFILE:-maestro-notary}"
TAP_DIR="${MAESTRO_TAP_DIR:-../homebrew-tap}"
REPO="kelvynkrug/maestro"

# O Sparkle compara CFBundleVersion entre o app instalado e o appcast:
# mantém em sincronia com a versão de marketing.
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" packaging/Info.plist

./scripts/build-app.sh

APP=dist/Maestro.app
SPARKLE_FW="$APP/Contents/Frameworks/Sparkle.framework"

echo "→ Assinando com '$IDENTITY' (hardened runtime, componentes do Sparkle primeiro)…"
codesign -f -o runtime --timestamp --preserve-metadata=entitlements -s "$IDENTITY" \
  "$SPARKLE_FW/Versions/B/XPCServices/Downloader.xpc"
codesign -f -o runtime --timestamp --preserve-metadata=entitlements -s "$IDENTITY" \
  "$SPARKLE_FW/Versions/B/XPCServices/Installer.xpc"
codesign -f -o runtime --timestamp -s "$IDENTITY" "$SPARKLE_FW/Versions/B/Autoupdate"
codesign -f -o runtime --timestamp -s "$IDENTITY" "$SPARKLE_FW/Versions/B/Updater.app"
codesign -f -o runtime --timestamp -s "$IDENTITY" "$SPARKLE_FW"
codesign -f -o runtime --timestamp \
  --entitlements packaging/entitlements.plist \
  -s "$IDENTITY" "$APP"

ZIP="dist/Maestro-$VERSION.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "→ Notarizando (aguarda a Apple responder)…"
if [ -n "${APP_STORE_CONNECT_KEY_ID:-}" ]; then
  xcrun notarytool submit "$ZIP" --wait \
    --key "$APP_STORE_CONNECT_PRIVATE_KEY_PATH" \
    --key-id "$APP_STORE_CONNECT_KEY_ID" \
    --issuer "$APP_STORE_CONNECT_ISSUER_ID"
else
  xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait
fi

echo "→ Grampeando o ticket no app…"
xcrun stapler staple "$APP"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "→ Gerando appcast assinado (Sparkle)…"
SIGN_UPDATE=$(find .build/artifacts -type f -name sign_update -not -path "*old_dsa*" | head -1)
SIGNATURE_AND_LENGTH=$("$SIGN_UPDATE" "$ZIP")
cat > dist/appcast.xml <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Maestro</title>
    <item>
      <title>Maestro $VERSION</title>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <enclosure
        url="https://github.com/$REPO/releases/download/v$VERSION/Maestro-$VERSION.zip"
        $SIGNATURE_AND_LENGTH
        type="application/octet-stream"/>
    </item>
  </channel>
</rss>
EOF

echo "→ Publicando GitHub Release v$VERSION…"
gh release create "v$VERSION" "$ZIP" dist/appcast.xml --repo "$REPO" \
  --title "Maestro v$VERSION" --generate-notes \
  || gh release upload "v$VERSION" "$ZIP" dist/appcast.xml --repo "$REPO" --clobber

echo "→ Atualizando cask no tap ($TAP_DIR)…"
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
sed -i '' \
  -e "s/version \".*\"/version \"$VERSION\"/" \
  -e "s/sha256 \".*\"/sha256 \"$SHA\"/" \
  "$TAP_DIR/Casks/maestro.rb"
git -C "$TAP_DIR" commit -am "maestro $VERSION"
git -C "$TAP_DIR" push

echo ""
echo "✅ Release v$VERSION publicada (GitHub Release + appcast + cask)."
echo "   Se o packaging/Info.plist mudou, commite o bump de versão."
