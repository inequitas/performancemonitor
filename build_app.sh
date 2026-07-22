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

BUILD_DIR=".build/release"
# The assembled .app lives under the hidden .build/ directory, not dist/, so
# Spotlight never indexes it (and never surfaces a stray, unsigned/ad-hoc-signed
# "Performance Monitor" as a search result). Only the zip (+ .sig) goes to dist/.
BUNDLE_DIR=".build/bundle"
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

# Assembles one app-bundle variant (stable or beta) from the single compiled
# binary above and packages it into dist/<zip_basename>.zip(.sig). Called
# once for a plain build, and TWICE for --beta (stable then beta) so a beta
# CI/release run always produces both assets from identical source — the
# stable variant differs from a plain (non---beta) build only in which of
# these bundle-level values (name/id/channel/icon) it's stamped with, never
# in the compiled code itself.
assemble_variant() {
    local app_name="$1" bundle_id="$2" channel="$3" zip_basename="$4" icon_src="$5"
    local app_dir="${BUNDLE_DIR}/${app_name}.app"

    if [ "$channel" = "beta" ]; then
        echo "Preparing beta app icon (cached — only regenerated when the source icon changes)..."
        bash scripts/build_beta_icon.sh
    fi

    echo "Assembling ${app_name}.app bundle..."
    mkdir -p "${BUNDLE_DIR}"
    rm -rf "${app_dir}"
    mkdir -p "${app_dir}/Contents/MacOS"
    mkdir -p "${app_dir}/Contents/Resources"

    cp "${BUILD_DIR}/PerformanceApp" "${app_dir}/Contents/MacOS/${app_name}"
    chmod +x "${app_dir}/Contents/MacOS/${app_name}"

    if [ -f "${icon_src}" ]; then
        cp "${icon_src}" "${app_dir}/Contents/Resources/AppIcon.icns"
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
        mkdir -p "${app_dir}/Contents/Resources/${LPROJ_NAME}"
        cp "${LANG_DIR}/"*.strings "${app_dir}/Contents/Resources/${LPROJ_NAME}/"
    done

    cat > "${app_dir}/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${app_name}</string>
    <key>CFBundleIdentifier</key>
    <string>${bundle_id}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleName</key>
    <string>${app_name}</string>
    <key>CFBundleDisplayName</key>
    <string>${app_name}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>PMUpdateChannel</key>
    <string>${channel}</string>
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
    codesign --force --deep --sign - "${app_dir}"

    # Package the app into a zip for distribution via GitHub Releases. dist/ is
    # kept to just the zip + its signature — the app bundle itself never lands
    # there (see BUNDLE_DIR above).
    mkdir -p dist
    local zip_path="dist/${zip_basename}.zip"
    echo "Packaging ${zip_path}..."
    rm -f "${zip_path}" "${zip_path}.sig"
    ditto -c -k --keepParent "${app_dir}" "${zip_path}"

    # Sign the zip for verified auto-updates. The app verifies this signature
    # (see UpdateChecker.swift) before unpacking any download. Signing needs the
    # private key; without it we warn but do not fail (e.g. CI without the secret).
    local private_key="scripts/private_key.txt"
    if [ -f "${private_key}" ]; then
        echo "Signing ${zip_path}..."
        swift scripts/sign_release.swift "${zip_path}"
        echo "Signature written: ${zip_path}.sig"
    else
        echo "WARNING: ${private_key} not found — ${zip_path} was NOT signed."
        echo "         Auto-updating clients will refuse an unsigned release."
        echo "         Run scripts/generate_keys.swift once to create the signing key."
    fi

    echo "Done: ${app_dir}"
    echo "Install locally with:"
    echo "  ditto \"${app_dir}\" \"/Applications/${app_name}.app\""
}

if [ "$BETA" = true ]; then
    # A beta CI/release run builds BOTH variants from this one compiled
    # binary: the stable variant (dist/PerformanceApp.zip) exactly as a
    # plain `build_app.sh` run would produce, plus the beta variant
    # (dist/PerformanceApp-Beta.zip). Both ship in the same GitHub release,
    # so the update checker's per-channel asset selection (AssetSelector)
    # always finds the right one by exact name.
    assemble_variant "Performance Monitor" "com.performancemonitor" "stable" "PerformanceApp" "icon/AppIcon.icns"
    assemble_variant "Performance Monitor Beta" "com.performancemonitor.beta" "beta" "PerformanceApp-Beta" "icon/AppIconBeta.icns"
    echo "(dist/ contains PerformanceApp.zip(.sig) and PerformanceApp-Beta.zip(.sig) — ${BUNDLE_DIR} is hidden from Spotlight.)"
    echo "Upload ALL FOUR files to the GitHub Release."
else
    assemble_variant "Performance Monitor" "com.performancemonitor" "stable" "PerformanceApp" "icon/AppIcon.icns"
    echo "(dist/ contains only PerformanceApp.zip(.sig) — ${BUNDLE_DIR} is hidden from Spotlight.)"
    echo "Upload BOTH dist/PerformanceApp.zip and dist/PerformanceApp.zip.sig to the GitHub Release."
fi
