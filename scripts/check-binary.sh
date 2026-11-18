#!/bin/bash
# Fails if a built binary can reach the network, launch programs, or load code at
# runtime. Run by scripts/build.sh on every build.
#
#   scripts/check-binary.sh build/spacehop
#
# Three independent checks, so one blind spot does not hide a problem:
#   1. linked libraries must all be on an allowlist (otool -L)
#   2. imported symbols must not be on a denylist (nm -u)
#   3. Objective-C selector/class strings must not be on a denylist (strings)
set -uo pipefail

BIN="${1:?usage: check-binary.sh <binary>}"
[ -f "$BIN" ] || { echo "check-binary: no such file: $BIN" >&2; exit 2; }
bad=0
report() { echo "check-binary: $1" >&2; bad=1; }

# 1. Libraries. Anything not matching one of these lines fails.
ALLOWED_LIBS='^/usr/lib/libSystem\.B\.dylib$
^/usr/lib/libobjc\.A\.dylib$
^/usr/lib/swift/libswift[A-Za-z_]*\.dylib$
^/System/Library/Frameworks/(Foundation|AppKit|Cocoa|Carbon|ApplicationServices|CoreFoundation|CoreGraphics|CoreServices)\.framework/
^/System/Library/PrivateFrameworks/SkyLight\.framework/'
while read -r lib; do
    [ -z "$lib" ] && continue
    echo "$lib" | grep -Eq "$ALLOWED_LIBS" || report "library not allowed: $lib"
done < <(otool -L "$BIN" | tail -n +2 | awk '{print $1}')

# 2. Imported symbols.
DENIED_SYMBOLS='^_(socket|socketpair|connect|bind|listen|accept|sendto|recvfrom|getaddrinfo|gethostbyname)$
^_(posix_spawn|posix_spawnp|execv|execve|execvp|execl|execle|execlp|fork|vfork|system|popen)$
^_(dlopen|dlsym|NSCreateObjectFileImageFromMemory|NSLinkModule)$
^_CFSocket
^_CFStream
^_CFHTTP
^_CFURLConnection
^_nw_
^_OBJC_CLASS_\$_(NSURLSession|NSURLConnection|NSURLDownload|NSTask|NSXPCConnection|NSNetService|NSStream|NSInputStream|NSOutputStream|NSAppleScript|NSUserScriptTask|NSBundle)$'
while read -r sym; do
    report "denied symbol: $sym"
done < <(nm -u "$BIN" | grep -E "$DENIED_SYMBOLS")

# 3. Selector and class-name strings (catches calls that go through objc_msgSend).
DENIED_STRINGS='URLSession|NSURLConnection|NSTask|openURL:|openURLs:|launchApplication|openApplicationAtURL|NSAppleScript|executeAndReturnError'
while read -r s; do
    report "denied string: $s"
done < <(strings -a "$BIN" | grep -E "$DENIED_STRINGS" | sort -u)

if [ "$bad" -ne 0 ]; then
    echo "check-binary: FAILED for $BIN" >&2
    exit 1
fi
echo "check-binary: OK ($BIN)"
