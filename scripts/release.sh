#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# release.sh — automates the Performance Monitor release process.
#
# Usage:
#   scripts/release.sh [VERSION] [--publish]
#   scripts/release.sh VERSION --beta [--publish]
#
# Without --publish, the script stops right after the build with a dry-run
# summary — nothing is tagged or published. VERSION defaults to the contents
# of VERSION; passing it explicitly overrides (but does not write back to)
# that file.
#
# Stable releases (no --beta) require an X.Y.Z version and behave exactly as
# before. Beta releases (--beta) require an X.Y.Z-beta.N version, build with
# build_app.sh --beta, and publish with `gh release create --prerelease`. A
# beta version without --beta (or vice versa) is rejected.
#
# Steps:
#   a) resolve + validate the version (and channel)
#   b) require a clean git working tree
#   c) stable: require a CHANGELOG.md section for that version — if none
#      exists but an "## Unreleased" heading does, it is renamed to the
#      version + today's date (the only automatic rewrite this script
#      performs; everything else about the changelog is checked, never
#      rewritten). beta: a CHANGELOG.md section is used if present, but not
#      required — falls back to short default release notes.
#   d) swift test && bash build_app.sh [--beta]
#   e) [--publish only] git tag vVERSION
#   f) [--publish only] gh release create vVERSION <zip> <zip>.sig
#      --title <title> --notes-file <notes> [--prerelease for beta]
#   g) [--publish, stable only] best-effort scripts/update_tap.sh bump of the
#      Homebrew cask in inequitas/homebrew-tap — a failure here warns but
#      never fails the release, which has already succeeded by this point.

PUBLISH=false
BETA=false
VERSION_ARG=""
for arg in "$@"; do
    case "$arg" in
        --publish) PUBLISH=true ;;
        --beta) BETA=true ;;
        -*) echo "Unknown flag: $arg" >&2; exit 1 ;;
        *) VERSION_ARG="$arg" ;;
    esac
done

# --- (a) resolve + validate version + channel --------------------------------
if [ -n "$VERSION_ARG" ]; then
    VERSION="$VERSION_ARG"
else
    VERSION="$(tr -d '[:space:]' < VERSION)"
fi

STABLE_VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+$'
BETA_VERSION_RE='^[0-9]+\.[0-9]+\.[0-9]+-beta\.[0-9]+$'

if [ "$BETA" = true ]; then
    if ! [[ "$VERSION" =~ $BETA_VERSION_RE ]]; then
        echo "ERROR: --beta requires a version like X.Y.Z-beta.N (got '${VERSION}')." >&2
        exit 1
    fi
else
    if [[ "$VERSION" =~ $BETA_VERSION_RE ]]; then
        echo "ERROR: version '${VERSION}' is a beta version — pass --beta." >&2
        exit 1
    fi
    if ! [[ "$VERSION" =~ $STABLE_VERSION_RE ]]; then
        echo "ERROR: version '${VERSION}' is not in X.Y.Z format." >&2
        exit 1
    fi
fi
TAG="v${VERSION}"
echo "==> Version: ${VERSION} (tag ${TAG}, channel $([ "$BETA" = true ] && echo beta || echo stable))"

# --- (b) clean working tree --------------------------------------------------
if [ -n "$(git status --porcelain)" ]; then
    echo "ERROR: working tree is not clean. Commit or stash changes first." >&2
    git status --short
    exit 1
fi
echo "==> Working tree is clean."

# --- (c) CHANGELOG.md section (required for stable, optional for beta) -------
CHANGELOG="CHANGELOG.md"
VERSION_HEADING_RE="^#{2,3}[[:space:]]+v${VERSION}([[:space:]]|\$)"
DEFAULT_BETA_NOTES="Beta build ${TAG}. See CHANGELOG.md (Unreleased) for in-progress changes — beta releases don't require their own changelog section. This is a pre-release, offered only to installs on the beta update channel."

if [ "$BETA" = true ] && ! grep -qE "$VERSION_HEADING_RE" "$CHANGELOG"; then
    TITLE="${TAG}"
    NOTES_FILE="$(mktemp -t release-notes)"
    printf '%s\n' "$DEFAULT_BETA_NOTES" > "$NOTES_FILE"
    echo "==> No CHANGELOG.md section for ${TAG} — using default beta release notes (not required for beta)."
else
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
fi

# --- (d) test + build ----------------------------------------------------
echo "==> Running swift test..."
# PM_SWIFT_TEST_FLAGS: extra flags for machines where Testing.framework is not
# on the default search path (Command Line Tools without full Xcode), e.g.
#   PM_SWIFT_TEST_FLAGS="-Xswiftc -F -Xswiftc /Library/Developer/CommandLineTools/Library/Developer/Frameworks"
# shellcheck disable=SC2086
swift test ${PM_SWIFT_TEST_FLAGS:-}

echo "==> Running build_app.sh $([ "$BETA" = true ] && echo '--beta')..."
if [ "$BETA" = true ]; then
    bash build_app.sh --beta
    ZIP_PATH="dist/PerformanceApp-Beta.zip"
else
    bash build_app.sh
    ZIP_PATH="dist/PerformanceApp.zip"
fi

if [ "$PUBLISH" != true ]; then
    echo ""
    echo "==> Dry run complete — nothing was tagged or published."
    echo "    Version:   ${VERSION}"
    echo "    Channel:   $([ "$BETA" = true ] && echo beta || echo stable)"
    echo "    Tag:       ${TAG}"
    echo "    Title:     ${TITLE}"
    echo "    Build:     ${ZIP_PATH}"
    if [ -f "${ZIP_PATH}.sig" ]; then
        echo "    Signature: ${ZIP_PATH}.sig (present)"
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
if [ ! -f "$ZIP_PATH" ] || [ ! -f "${ZIP_PATH}.sig" ]; then
    echo "ERROR: ${ZIP_PATH}(.sig) missing — cannot publish an unsigned/missing build." >&2
    exit 1
fi

echo "==> Publishing GitHub release ${TAG}..."
if [ "$BETA" = true ]; then
    gh release create "$TAG" "$ZIP_PATH" "${ZIP_PATH}.sig" \
        --title "${TITLE}" \
        --notes-file "$NOTES_FILE" \
        --prerelease
else
    gh release create "$TAG" "$ZIP_PATH" "${ZIP_PATH}.sig" \
        --title "${TITLE}" \
        --notes-file "$NOTES_FILE"
fi

echo "==> Released ${TAG}."

# --- (g) best-effort Homebrew tap bump (stable only) ------------------------
if [ "$BETA" = false ]; then
    echo "==> Updating Homebrew tap..."
    if ! bash scripts/update_tap.sh "$VERSION" "$ZIP_PATH"; then
        echo "WARNING: failed to update inequitas/homebrew-tap for ${TAG}." >&2
        echo "         The GitHub release itself succeeded — update the cask manually:" >&2
        echo "         scripts/update_tap.sh ${VERSION} ${ZIP_PATH}" >&2
    fi
fi
