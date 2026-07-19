#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# release.sh — automates the Performance Monitor release process.
#
# Usage:
#   scripts/release.sh [VERSION] [--publish]
#
# Without --publish, the script stops right after the build with a dry-run
# summary — nothing is tagged or published. VERSION defaults to the contents
# of VERSION; passing it explicitly overrides (but does not write back to)
# that file.
#
# Steps:
#   a) resolve + validate the version
#   b) require a clean git working tree
#   c) require a CHANGELOG.md section for that version — if none exists but
#      an "## Unreleased" heading does, it is renamed to the version + today's
#      date (the only automatic rewrite this script performs; everything
#      else about the changelog is checked, never rewritten)
#   d) swift test && bash build_app.sh
#   e) [--publish only] git tag vVERSION
#   f) [--publish only] gh release create vVERSION dist/PerformanceApp.zip
#      dist/PerformanceApp.zip.sig --title <changelog heading> --notes-file <changelog section>

PUBLISH=false
VERSION_ARG=""
for arg in "$@"; do
    case "$arg" in
        --publish) PUBLISH=true ;;
        -*) echo "Unknown flag: $arg" >&2; exit 1 ;;
        *) VERSION_ARG="$arg" ;;
    esac
done

# --- (a) resolve + validate version -----------------------------------------
if [ -n "$VERSION_ARG" ]; then
    VERSION="$VERSION_ARG"
else
    VERSION="$(tr -d '[:space:]' < VERSION)"
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: version '${VERSION}' is not in X.Y.Z format." >&2
    exit 1
fi
TAG="v${VERSION}"
echo "==> Version: ${VERSION} (tag ${TAG})"

# --- (b) clean working tree --------------------------------------------------
if [ -n "$(git status --porcelain)" ]; then
    echo "ERROR: working tree is not clean. Commit or stash changes first." >&2
    git status --short
    exit 1
fi
echo "==> Working tree is clean."

# --- (c) CHANGELOG.md has a section for this version -------------------------
CHANGELOG="CHANGELOG.md"
VERSION_HEADING_RE="^#{2,3}[[:space:]]+v${VERSION}([[:space:]]|\$)"

if ! grep -qE "$VERSION_HEADING_RE" "$CHANGELOG"; then
    if grep -qE '^##[[:space:]]+Unreleased([[:space:]]|$)' "$CHANGELOG"; then
        TODAY="$(date +%Y-%m-%d)"
        echo "==> Renaming '## Unreleased' -> '## ${TAG} *(${TODAY})*' in ${CHANGELOG}..."
        # Only the single heading line is rewritten; every other line
        # (including the rest of that section's body) is left untouched.
        sed -i '' -E "s/^##[[:space:]]+Unreleased([[:space:]]|\$).*/## ${TAG} *(${TODAY})*/" "$CHANGELOG"
    else
        echo "ERROR: ${CHANGELOG} has no section for ${TAG} and no 'Unreleased' heading to rename." >&2
        echo "       Add a '## ${TAG}' (or '### ${TAG}') section before releasing." >&2
        exit 1
    fi
fi
echo "==> CHANGELOG.md has a section for ${TAG}."

# Extract that section (heading + body, up to the next ##/### heading) for
# the GitHub release title/notes.
HEADING_LINE="$(grep -E "$VERSION_HEADING_RE" "$CHANGELOG" | head -1)"
TITLE="$(printf '%s' "$HEADING_LINE" | sed -E 's/^#{2,3}[[:space:]]+//; s/[[:space:]]*\*\([^)]*\)\*[[:space:]]*$//')"

NOTES_FILE="$(mktemp -t release-notes)"
awk -v re="$VERSION_HEADING_RE" '
    $0 ~ re { found=1; next }
    found && /^#{2,3}[[:space:]]/ { exit }
    found { print }
' "$CHANGELOG" > "$NOTES_FILE"

if [ ! -s "$NOTES_FILE" ]; then
    echo "ERROR: could not extract a non-empty changelog section for ${TAG}." >&2
    exit 1
fi

# --- (d) test + build ----------------------------------------------------
echo "==> Running swift test..."
swift test

echo "==> Running build_app.sh..."
bash build_app.sh

if [ "$PUBLISH" != true ]; then
    echo ""
    echo "==> Dry run complete — nothing was tagged or published."
    echo "    Version:   ${VERSION}"
    echo "    Tag:       ${TAG}"
    echo "    Title:     ${TITLE}"
    echo "    Build:     dist/PerformanceApp.zip"
    if [ -f dist/PerformanceApp.zip.sig ]; then
        echo "    Signature: dist/PerformanceApp.zip.sig (present)"
    else
        echo "    Signature: MISSING — signed updates need scripts/private_key.txt"
    fi
    echo "    Notes:     ${NOTES_FILE}"
    echo ""
    echo "Re-run with --publish to tag and publish this release."
    exit 0
fi

# --- (e) tag -------------------------------------------------------------
echo "==> Tagging ${TAG}..."
git tag "$TAG"

# --- (f) publish -----------------------------------------------------------
if [ ! -f dist/PerformanceApp.zip ] || [ ! -f dist/PerformanceApp.zip.sig ]; then
    echo "ERROR: dist/PerformanceApp.zip(.sig) missing — cannot publish an unsigned/missing build." >&2
    exit 1
fi

echo "==> Publishing GitHub release ${TAG}..."
gh release create "$TAG" dist/PerformanceApp.zip dist/PerformanceApp.zip.sig \
    --title "${TITLE}" \
    --notes-file "$NOTES_FILE"

echo "==> Released ${TAG}."
