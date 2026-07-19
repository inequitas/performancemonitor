#!/bin/bash
# Builds icon/AppIconBeta.icns from icon/Icon-1024.png with a "BETA" badge
# drawn on top (see scripts/generate_beta_icon.swift). Called by
# build_app.sh --beta. Result is cached: re-run is a no-op unless the
# source icon or the badge script changed since the last build.
set -euo pipefail
cd "$(dirname "$0")/.."

SRC_PNG="icon/Icon-1024.png"
BADGE_SCRIPT="scripts/generate_beta_icon.swift"
BADGED_PNG="icon/Icon-1024-beta.png"
ICONSET_DIR="icon/AppIconBeta.iconset"
BETA_ICNS="icon/AppIconBeta.icns"

if [ -f "${BETA_ICNS}" ] \
    && [ "${BETA_ICNS}" -nt "${SRC_PNG}" ] \
    && [ "${BETA_ICNS}" -nt "${BADGE_SCRIPT}" ]; then
    echo "Beta icon up to date: ${BETA_ICNS}"
    exit 0
fi

echo "Generating beta-badged icon master..."
swift "${BADGE_SCRIPT}" "${SRC_PNG}" "${BADGED_PNG}"

echo "Building ${ICONSET_DIR} from badged master..."
rm -rf "${ICONSET_DIR}"
mkdir -p "${ICONSET_DIR}"

# Same file/size pairing as icon/AppIcon.iconset, resized from the badged master.
SIZES=(
    "icon_16x16.png:16"
    "icon_16x16@2x.png:32"
    "icon_32x32.png:32"
    "icon_32x32@2x.png:64"
    "icon_64x64.png:64"
    "icon_64x64@2x.png:128"
    "icon_128x128.png:128"
    "icon_128x128@2x.png:256"
    "icon_256x256.png:256"
    "icon_256x256@2x.png:512"
    "icon_512x512.png:512"
    "icon_512x512@2x.png:1024"
    "icon_1024x1024.png:1024"
)

for entry in "${SIZES[@]}"; do
    name="${entry%%:*}"
    px="${entry##*:}"
    sips -z "${px}" "${px}" "${BADGED_PNG}" --out "${ICONSET_DIR}/${name}" >/dev/null
done

echo "Compiling ${BETA_ICNS}..."
iconutil -c icns "${ICONSET_DIR}" -o "${BETA_ICNS}"
echo "Wrote ${BETA_ICNS}"
