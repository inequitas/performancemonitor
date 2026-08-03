#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

# test.sh — runs `swift test`, adding the flags a Command-Line-Tools-only Mac
# needs to find swift-testing.
#
# Usage:
#   scripts/test.sh [extra swift test args...]
#   scripts/test.sh --filter DiskIORates
#
# With full Xcode installed, swift-testing is on the default search path and
# this is a plain `swift test`. With only the Command Line Tools it is not, and
# `swift test` fails with "no such module 'Testing'" at compile time — and then,
# once -F fixes that, with a dlopen failure for lib_TestingInterop.dylib at run
# time. Three flags are needed, not one:
#
#   -F <Frameworks>          so the compiler finds Testing.framework
#   -rpath <Frameworks>      so the test bundle can load Testing at run time
#   -rpath <Developer/usr/lib>  so Testing can load lib_TestingInterop.dylib,
#                               which lives in a *different* directory
#
# Everything is derived from `xcode-select -p`, so this keeps working if the
# active developer directory moves.
#
# PM_SWIFT_TEST_FLAGS overrides the auto-detection entirely when set.

DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
FRAMEWORKS="${DEVELOPER_DIR}/Library/Developer/Frameworks"
INTEROP_LIB_DIR="${DEVELOPER_DIR}/Library/Developer/usr/lib"

FLAGS=()
if [ -n "${PM_SWIFT_TEST_FLAGS:-}" ]; then
    # Deliberate word splitting: the variable holds multiple flags.
    # shellcheck disable=SC2206
    FLAGS=(${PM_SWIFT_TEST_FLAGS})
    echo "==> Using PM_SWIFT_TEST_FLAGS override"
elif [ -d "${FRAMEWORKS}/Testing.framework" ]; then
    FLAGS=(-Xswiftc -F -Xswiftc "${FRAMEWORKS}"
           -Xlinker -rpath -Xlinker "${FRAMEWORKS}")
    if [ -f "${INTEROP_LIB_DIR}/lib_TestingInterop.dylib" ]; then
        FLAGS+=(-Xlinker -rpath -Xlinker "${INTEROP_LIB_DIR}")
    fi
    echo "==> swift-testing found under ${DEVELOPER_DIR}; adding search paths"
fi

# ${FLAGS[@]+...} rather than "${FLAGS[@]}": under `set -u`, bash 3.2 (which
# is what macOS ships) treats an empty array as unbound and aborts. FLAGS is
# empty on any machine with full Xcode, where no extra search paths are
# needed, so that is the normal case rather than an edge one.
exec swift test ${FLAGS[@]+"${FLAGS[@]}"} "$@"
