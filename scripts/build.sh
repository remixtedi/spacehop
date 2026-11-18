#!/bin/bash
# Builds build/spacehop, signs it, and scans it. Fails if the scan fails.
#
#   scripts/build.sh          build, sign, scan
#   scripts/build.sh --test   build and run the unit tests (no signing, no scan)
set -euo pipefail
cd "$(dirname "$0")/.."

SWIFTC=(swiftc -O -F /System/Library/PrivateFrameworks -framework SkyLight)
mkdir -p build

if [ "${1:-}" = "--test" ]; then
    # Everything except the entry point, plus the test files (tests/main.swift is their entry point).
    SOURCES=()
    for f in Sources/*.swift; do [ "$(basename "$f")" = "main.swift" ] || SOURCES+=("$f"); done
    "${SWIFTC[@]}" "${SOURCES[@]}" tests/*.swift -o build/spacehop-tests
    build/spacehop-tests
    exit $?
fi

"${SWIFTC[@]}" Sources/*.swift -o build/spacehop

IDENTITY="spacehop local signing"
KEYCHAIN="$HOME/Library/Keychains/spacehop-signing.keychain-db"
SECRET_FILE="$HOME/.config/spacehop/signing-keychain-password"
if [ -f "$KEYCHAIN" ] && [ -f "$SECRET_FILE" ]; then
    security unlock-keychain -p "$(cat "$SECRET_FILE")" "$KEYCHAIN"
    codesign --force --sign "$IDENTITY" --keychain "$KEYCHAIN" --identifier com.remixtedi.spacehop build/spacehop
else
    echo "No local signing identity (run scripts/setup-signing.sh). Using an ad-hoc signature:" >&2
    echo "the Accessibility grant must be given again after each build." >&2
    codesign --force --sign - --identifier com.remixtedi.spacehop build/spacehop
fi

scripts/check-binary.sh build/spacehop
echo "Built build/spacehop"
