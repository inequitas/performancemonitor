#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

BETA=false
for arg in "$@"; do
    case "$arg" in
        --beta) BETA=true ;;
        *) echo "Unknown flag: $arg" >&2; exit 1 ;;
    esac
done

if [ "$BETA" = true ]; then
    APP_NAME="Performance Monitor Beta"
    BUNDLE_ID="com.performancemonitor.beta"
    CHANNEL="beta"
    ZIP_BASENAME="PerformanceApp-Beta"
    ICON_SRC="icon/AppIconBeta.icns"
else
    APP_NAME="Performance Monitor"
    BUNDLE_ID="com.performancemonitor"
    CHANNEL="stable"
    ZIP_BASENAME="PerformanceApp"
    ICON_SRC="icon/AppIcon.icns"
fi

BUILD_DIR=".build/release"
# The assembled .app lives under the hidden .build/ directory, not dist/, so
# Spotlight never indexes it (and never surfaces a stray, unsigned/ad-hoc-signed
# "Performance Monitor" as a search result). Only the zip (+ .sig) goes to dist/.
BUNDLE_DIR=".build/bundle"
APP_DIR="${BUNDLE_DIR}/${APP_NAME}.app"
VERSION="$(cat VERSION | tr -d '[:space:]')"

echo "Building release binary (arm64-only)..."
swift build -c release --arch arm64

# This app targets Apple Silicon exclusively (no Intel fallback, no dependencies
# that need a universal slice). Guard against an accidental universal/x86_64
# build slipping into a release artifact.
BUILT_ARCHS="$(lipo -archs "${BUILD_DIR}/PerformanceApp")"
if [ "${BUILT_ARCHS}" != "arm64" ]; then
    echo "ERROR: expected an arm64-only binary, got architectures: ${BUILT_ARCHS}"
    exit 1
fi

if [ "$BETA" = true ]; then
    echo "Preparing beta app icon (cached — only regenerated when the source icon changes)..."
    bash scripts/build_beta_icon.sh
fi

echo "Assembling .app bundle..."
mkdir -p "${BUNDLE_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/PerformanceApp" "${APP_DIR}/Contents/MacOS/${APP_NAME}"
chmod +x "${APP_DIR}/Contents/MacOS/${APP_NAME}"

if [ -f "${ICON_SRC}" ]; then
    cp "${ICON_SRC}" "${APP_DIR}/Contents/Resources/AppIcon.icns"
fi

# Localization: In-app UI strings (String(localized:), no explicit bundle)
# resolve against Bundle.main, which CFBundle maps to Contents/Resources/
# <lang>.lproj at runtime — the standard mechanism, verified to correctly
# honor the user's language preference. We deliberately do NOT use SwiftPM's
# generated Bundle.module accessor here: its resource_bundle_accessor.swift
# looks for the resource bundle via `Bundle.main.bundleURL.appendingPathComponent(...)`,
# i.e. at the TOP LEVEL of the .app (sibling of Contents/) — but codesign
# rejects that layout ("unsealed contents present in the bundle root"). Bundle.module
# remains available for `swift build`/`swift test` during development (it
# falls back to the raw .build path there), but the shipped .app copies the
# same source-of-truth .lproj files straight into Contents/Resources instead.
#
# Two source trees feed Contents/Resources/<lang>.lproj:
#   - Sources/PerformanceApp/Resources/<lang>.lproj  (Localizable.strings — UI strings)
#   - Resources/<lang>.lproj                          (InfoPlist.strings — system prompts)
for LANG_DIR in Sources/PerformanceApp/Resources/*.lproj Resources/*.lproj; do
    LPROJ_NAME="$(basename "${LANG_DIR}")"
    mkdir -p "${APP_DIR}/Contents/Resources/${LPROJ_NAME}"
    cp "${LANG_DIR}/"*.strings "${APP_DIR}/Contents/Resources/${LPROJ_NAME}/"
done

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
    <key>PMUpdateChannel</key>
    <string>${CHANNEL}</string>
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

# Package the app into a zip for distribution via GitHub Releases. dist/ is
# kept to just the zip + its signature — the app bundle itself never lands
# there (see BUNDLE_DIR above).
mkdir -p dist
ZIP_PATH="dist/${ZIP_BASENAME}.zip"
echo "Packaging ${ZIP_PATH}..."
rm -f "${ZIP_PATH}" "${ZIP_PATH}.sig"
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
echo "(dist/ contains only ${ZIP_PATH}(.sig) — ${BUNDLE_DIR} is hidden from Spotlight.)"
echo "Install locally with:"
echo "  ditto \"${APP_DIR}\" \"/Applications/${APP_NAME}.app\""
echo "Upload BOTH ${ZIP_PATH} and ${ZIP_PATH}.sig to the GitHub Release."
