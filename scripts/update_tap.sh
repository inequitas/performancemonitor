#!/bin/bash
set -euo pipefail

# update_tap.sh — bumps the Homebrew cask in inequitas/homebrew-tap to match
# a freshly published stable release.
#
# Usage: scripts/update_tap.sh VERSION ZIP_PATH
#   VERSION   e.g. 1.0.1 (no leading "v")
#   ZIP_PATH  path to the built dist/PerformanceApp.zip for that version
#
# Called from release.sh after a successful `gh release create` for a stable
# release only. Failures here are reported but must never fail the release
# itself — the caller treats this as best-effort.

VERSION="${1:?Usage: update_tap.sh VERSION ZIP_PATH}"
ZIP_PATH="${2:?Usage: update_tap.sh VERSION ZIP_PATH}"

TAP_REPO="https://github.com/inequitas/homebrew-tap.git"
CASK_PATH="Casks/performance-monitor.rb"

if [ ! -f "$ZIP_PATH" ]; then
    echo "ERROR: ${ZIP_PATH} not found." >&2
    exit 1
fi

SHA256="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
echo "==> New cask version: ${VERSION} (sha256 ${SHA256})"

WORKDIR="$(mktemp -d -t homebrew-tap)"
trap 'rm -rf "$WORKDIR"' EXIT

echo "==> Cloning ${TAP_REPO}..."
git clone --quiet --depth 1 "$TAP_REPO" "$WORKDIR"

cd "$WORKDIR"

if [ ! -f "$CASK_PATH" ]; then
    echo "ERROR: ${CASK_PATH} not found in tap repo." >&2
    exit 1
fi

sed -i '' -E "s/^(  version \")[^\"]+(\")$/\1${VERSION}\2/" "$CASK_PATH"
sed -i '' -E "s/^(  sha256 \")[^\"]+(\")$/\1${SHA256}\2/" "$CASK_PATH"

if git diff --quiet -- "$CASK_PATH"; then
    echo "==> Cask already up to date — nothing to commit."
    exit 0
fi

git add "$CASK_PATH"
git commit --quiet -m "performance-monitor ${VERSION}"
git push --quiet origin main

echo "==> Tap updated to ${VERSION}."
