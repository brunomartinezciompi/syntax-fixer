#!/bin/bash
# Compila SyntaxFixer y arma el bundle .app (sin Xcode).
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="SyntaxFixer"
BUNDLE="build/$APP_NAME.app"

rm -rf build
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"

echo "→ compilando…"
swiftc -O \
  -target arm64-apple-macos14.0 \
  -framework AppKit -framework SwiftUI \
  -o "$BUNDLE/Contents/MacOS/$APP_NAME" \
  Sources/main.swift Sources/ContentView.swift Sources/ClaudeRunner.swift

echo "→ generando icono…"
ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
swift make-icon.swift "$ICONSET" >/dev/null
iconutil -c icns "$ICONSET" -o "$BUNDLE/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

cat > "$BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>SyntaxFixer</string>
    <key>CFBundleDisplayName</key>     <string>Syntax</string>
    <key>CFBundleExecutable</key>      <string>SyntaxFixer</string>
    <key>CFBundleIdentifier</key>      <string>com.brunomartinez.syntaxfixer</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>CFBundleIconFile</key>        <string>AppIcon</string>
    <key>NSHighResolutionCapable</key> <true/>
    <!-- Agente: sin icono en el Dock, sólo el panel flotante. -->
    <key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST

# Firma ad-hoc: sin esto macOS mata la app al lanzarla desde Finder.
codesign --force --deep --sign - "$BUNDLE" >/dev/null 2>&1 || true

echo "✓ listo: $(pwd)/$BUNDLE"
