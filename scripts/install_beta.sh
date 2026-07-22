#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# install_beta.sh — local dev helper: build the beta variant, install it fresh
# into /Applications, wipe its settings (so onboarding shows again), and launch.
#
#   scripts/install_beta.sh                  # clean install: fresh settings + onboarding
#   scripts/install_beta.sh --keep-settings  # upgrade-style install: settings survive
#
# Only affects the LOCAL test install (com.performancemonitor.beta domain).
# Released betas update through the in-app updater and always keep settings.

KEEP=false
[ "${1:-}" = "--keep-settings" ] && KEEP=true

bash build_app.sh --beta

pkill -f "Performance Monitor Beta" 2>/dev/null || true
sleep 1
rm -rf "/Applications/Performance Monitor Beta.app"
ditto ".build/bundle/Performance Monitor Beta.app" "/Applications/Performance Monitor Beta.app"

if [ "$KEEP" = false ]; then
    defaults delete com.performancemonitor.beta 2>/dev/null || true
    echo "==> Beta settings wiped — onboarding will show."
else
    echo "==> Settings kept (--keep-settings)."
fi

open "/Applications/Performance Monitor Beta.app"
echo "==> Launched fresh beta from /Applications."
