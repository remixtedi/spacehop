#!/bin/bash
# Proves scripts/check-binary.sh catches what it must: builds a clean program and
# programs that use networking, process launching, and dynamic loading, and checks
# the scanner passes only the clean one.
set -uo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
fails=0

build() { # name, source
    printf '%s\n' "$2" > "$WORK/$1.swift"
    swiftc -O "$WORK/$1.swift" -o "$WORK/$1" 2>"$WORK/$1.log" || { echo "could not build $1"; cat "$WORK/$1.log"; exit 1; }
}

expect() { # name, wanted exit code
    scripts/check-binary.sh "$WORK/$1" >"$WORK/$1.out" 2>&1
    local got=$?
    if [ "$got" -eq "$2" ]; then
        echo "ok   $1 (exit $got)"
    else
        echo "FAIL $1: wanted exit $2, got $got"; cat "$WORK/$1.out"; fails=$((fails + 1))
    fi
}

build clean 'import AppKit
print(NSApplication.shared.isActive)'
build net 'import Foundation
print(URLSession.shared)'
build spawn 'import Foundation
let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/echo"); try? p.run()'
build dyld 'import Darwin
print(dlopen("/usr/lib/libz.dylib", RTLD_NOW) as Any)'
build sock 'import Darwin
print(socket(AF_INET, SOCK_STREAM, 0))'

expect clean 0
expect net 1
expect spawn 1
expect dyld 1
expect sock 1

[ "$fails" -eq 0 ] && echo "check-binary-test: all passed" || { echo "check-binary-test: $fails failed"; exit 1; }
