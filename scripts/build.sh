#!/bin/bash
# Builds build/spacehop, signs it ad-hoc, and scans it. Fails if the scan fails.
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

# Ad-hoc signature: macOS ties the Accessibility grant to this exact build, so no
# other binary can inherit it. Cost: allow spacehop again after each rebuild.
codesign --force --sign - --identifier com.remixtedi.spacehop build/spacehop

scripts/check-binary.sh build/spacehop
echo "Built build/spacehop"
