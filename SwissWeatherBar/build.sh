#!/bin/zsh
set -e
cd "$(dirname "$0")"
APP="Swiss Weather Bar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -o "$APP/Contents/MacOS/SwissWeatherBar" Forecast.swift main.swift
cp places.tsv "$APP/Contents/Resources/"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SwissWeatherBar</string>
<key>CFBundleIdentifier</key><string>io.github.swissweatherbar</string>
<key>CFBundleName</key><string>Swiss Weather Bar</string>
<key>CFBundleDisplayName</key><string>Swiss Weather Bar</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSHumanReadableCopyright</key><string>Forecast data: Source: MeteoSwiss (CC BY 4.0). Not affiliated with MeteoSwiss.</string>
<key>NSLocationUsageDescription</key><string>Your location is used to show the forecast for the nearest Swiss postcode.</string>
<key>NSLocationWhenInUseUsageDescription</key><string>Your location is used to show the forecast for the nearest Swiss postcode.</string>
</dict></plist>
PLIST
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Built $APP"
