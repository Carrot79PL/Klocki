#!/bin/zsh
# Buduje Klocki.app z main.swift
set -e
cd "$(dirname "$0")"
APP=Klocki.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -target arm64-apple-macos14.0 -o "$APP/Contents/MacOS/Klocki" Music.swift Player.swift Intro.swift Intro3D.swift LogoData.swift Bake.swift PenSound.swift FilmSound.swift TMIntroView.swift TMIntroKit.swift main.swift -framework Cocoa -framework SceneKit -framework SpriteKit -framework AVFoundation -framework Metal -framework MetalKit -framework MetalPerformanceShaders
cp Resources/wordmark.svg Resources/blueroot.svg Resources/podpis_* "$APP/Contents/Resources/"
# ikona: generowana z Icon.swift, gdy jej brak albo skrypt ikony jest nowszy
if [ ! -f Resources/AppIcon.icns ] || [ Icon.swift -nt Resources/AppIcon.icns ]; then
  rm -rf build/AppIcon.iconset && mkdir -p build
  swift Icon.swift build/AppIcon.iconset && iconutil -c icns build/AppIcon.iconset -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Klocki</string>
  <key>CFBundleDisplayName</key><string>Klocki</string>
  <key>CFBundleIdentifier</key><string>pl.marchewka.klocki</string>
  <key>CFBundleExecutable</key><string>Klocki</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.2</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.puzzle-games</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
EOF
codesign --force -s - "$APP" >/dev/null 2>&1 || true
echo "Gotowe: $(pwd)/$APP"
