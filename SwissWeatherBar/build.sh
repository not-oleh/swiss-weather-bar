#!/bin/zsh
# Builds "Swiss Weather Bar.app" (universal: Apple Silicon + Intel).
# ./build.sh          build the app next to this script
# ./build.sh release  also create dist/Swiss-Weather-Bar-<version>.zip for a GitHub release
set -e
cd "$(dirname "$0")"
VERSION="1.0.0"
BUILD="1"
APP="Swiss Weather Bar.app"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
for ARCH in arm64 x86_64; do
  swiftc -O -target "$ARCH-apple-macos13.0" -o "$TMP/$ARCH" Forecast.swift main.swift
done
lipo -create "$TMP/arm64" "$TMP/x86_64" -output "$APP/Contents/MacOS/SwissWeatherBar"
cp places.tsv "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SwissWeatherBar</string>
<key>CFBundleIdentifier</key><string>io.github.swissweatherbar</string>
<key>CFBundleName</key><string>Swiss Weather Bar</string>
<key>CFBundleDisplayName</key><string>Swiss Weather Bar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$VERSION</string>
<key>CFBundleVersion</key><string>$BUILD</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Forecast data: Source: MeteoSwiss (CC BY 4.0). Not affiliated with MeteoSwiss.</string>
<key>NSLocationUsageDescription</key><string>Your location is used to show the forecast for the nearest Swiss postcode.</string>
<key>NSLocationWhenInUseUsageDescription</key><string>Your location is used to show the forecast for the nearest Swiss postcode.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Built $APP ($VERSION)"

if [[ "$1" == "release" ]]; then
  mkdir -p ../dist
  ZIP="../dist/Swiss-Weather-Bar-$VERSION.zip"
  rm -f "$ZIP"
  ditto -c -k --keepParent "$APP" "$ZIP"
  echo "Created ${ZIP#../}"
fi
