#!/bin/bash
# Fails if a built binary can reach the network, launch programs, talk to other
# processes, or load code at runtime. Run by scripts/build.sh on every build.
#
#   scripts/check-binary.sh build/spacehop
#
# Checks:
#   1. the file is a Mach-O binary and every inspection tool succeeds
#   2. linked libraries must all be on an allowlist (otool -L)
#   3. imported C/Objective-C symbols must all be on scripts/allowed-imports.txt (nm -u)
#   4. no Swift symbol may use Foundation's URL type (nm -u)
#   5. no Objective-C selector/class string on a denylist (strings)
# An allowlist rather than a denylist: anything new fails until reviewed.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

BIN="${1:?usage: check-binary.sh <binary>}"
[ -f "$BIN" ] || { echo "check-binary: no such file: $BIN" >&2; exit 2; }
ALLOWED_IMPORTS=scripts/allowed-imports.txt
bad=0
report() { echo "check-binary: $1" >&2; bad=1; }
fail_hard() { echo "check-binary: $1" >&2; echo "check-binary: FAILED for $BIN" >&2; exit 1; }

# 1. Inspect once; any tool failure fails the check.
lipo -archs "$BIN" >/dev/null 2>&1 || fail_hard "not a Mach-O binary"
LIBS="$(otool -L "$BIN")" || fail_hard "otool failed"
IMPORTS="$(nm -u "$BIN")" || fail_hard "nm failed"
STRINGS="$(strings -a "$BIN")" || fail_hard "strings failed"
[ -n "$IMPORTS" ] || fail_hard "nm returned no imports"
[ -f "$ALLOWED_IMPORTS" ] || fail_hard "missing $ALLOWED_IMPORTS"

# 2. Libraries.
ALLOWED_LIBS='^/usr/lib/libSystem\.B\.dylib$
^/usr/lib/libobjc\.A\.dylib$
^/usr/lib/swift/libswift[A-Za-z_]*\.dylib$
^/System/Library/Frameworks/(Foundation|AppKit|Cocoa|Carbon|ApplicationServices|CoreFoundation|CoreGraphics|CoreServices|ColorSync)\.framework/
^/System/Library/PrivateFrameworks/SkyLight\.framework/'
while read -r lib; do
    [ -z "$lib" ] && continue
    echo "$lib" | grep -Eq "$ALLOWED_LIBS" || report "library not allowed: $lib"
done < <(echo "$LIBS" | tail -n +2 | awk '{print $1}')

# 3. C and Objective-C imports: exact allowlist. Swift runtime and mangled Swift
# symbols are handled by check 4.
while read -r sym; do
    report "import not on allowlist: $sym"
done < <(echo "$IMPORTS" | grep -v '^_\$s' | grep -v '^__swift' | grep -v '^_swift_' |
         grep -vxF -f <(grep -v '^#' "$ALLOWED_IMPORTS"))

# 4. Swift symbols: spacehop uses no URL, so any use of Foundation.URL (which every
# Swift fetch, open, or bundle-load API takes) fails.
while read -r sym; do
    report "Swift symbol uses URL: $sym"
done < <(echo "$IMPORTS" | grep -E '10Foundation3URLV')

# 5. Selector and class-name strings (calls that go through objc_msgSend).
DENIED_STRINGS='URLSession|NSURLConnection|NSTask|openURL:|openURLs:|openFile|launchApplication|openApplicationAtURL|NSAppleScript|executeAndReturnError|NSXPCConnection'
while read -r s; do
    report "denied string: $s"
done < <(echo "$STRINGS" | grep -E "$DENIED_STRINGS" | sort -u)

if [ "$bad" -ne 0 ]; then
    echo "check-binary: FAILED for $BIN" >&2
    exit 1
fi
echo "check-binary: OK ($BIN)"
