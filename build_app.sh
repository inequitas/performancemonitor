#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Performance Monitor"
BUNDLE_ID="com.performancemonitor"
BUILD_DIR=".build/release"
APP_DIR="dist/${APP_NAME}.app"
VERSION="$(cat VERSION | tr -d '[:space:]')"

echo "Building release binary..."
swift build -c release

echo "Assembling .app bundle..."
rm -rf "dist"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/PerformanceApp" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"

if [ -f "icon/AppIcon.icns" ]; then
    cp "icon/AppIcon.icns" "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

cat > "${APP_DIR}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSUIElement</key>
    <true/>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHumanReadableCopyright</key>
    <string>Personal use</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Performance Monitor lists your paired Bluetooth devices and their connection status.</string>
</dict>
</plist>
PLIST

echo "Code signing (ad-hoc, no Developer ID available)..."
codesign --force --deep --sign - "${APP_DIR}"

# Package the app into a zip for distribution via GitHub Releases.
ZIP_PATH="dist/PerformanceApp.zip"
echo "Packaging ${ZIP_PATH}..."
ditto -c -k --keepParent "${APP_DIR}" "${ZIP_PATH}"

# Sign the zip for verified auto-updates. The app verifies this signature
# (see UpdateChecker.swift) before unpacking any download. Signing needs the
# private key; without it we warn but do not fail (e.g. CI without the secret).
PRIVATE_KEY="scripts/private_key.txt"
if [ -f "${PRIVATE_KEY}" ]; then
    echo "Signing ${ZIP_PATH}..."
    swift scripts/sign_release.swift "${ZIP_PATH}"
    echo "Signature written: ${ZIP_PATH}.sig"
else
    echo "WARNING: ${PRIVATE_KEY} not found — the release zip was NOT signed."
    echo "         Auto-updating clients will refuse an unsigned release."
    echo "         Run scripts/generate_keys.swift once to create the signing key."
fi

echo "Done: ${APP_DIR}"
echo "Run with: open \"${APP_DIR}\""
echo "Or move it to /Applications: mv \"${APP_DIR}\" /Applications/"
echo "Upload BOTH ${ZIP_PATH} and ${ZIP_PATH}.sig to the GitHub Release."
