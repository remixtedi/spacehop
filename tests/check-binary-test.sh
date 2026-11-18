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

# The real program is the clean case: the scanner must pass it.
swiftc -O -F /System/Library/PrivateFrameworks -framework SkyLight Sources/*.swift -o "$WORK/clean" 2>"$WORK/clean.log" || { echo "could not build spacehop"; cat "$WORK/clean.log"; exit 1; }
build net 'import Foundation
print(URLSession.shared)'
build spawn 'import Foundation
let p = Process(); p.executableURL = URL(fileURLWithPath: "/bin/echo"); try? p.run()'
build dyld 'import Darwin
print(dlopen("/usr/lib/libz.dylib", RTLD_NOW) as Any)'
build sock 'import Darwin
print(socket(AF_INET, SOCK_STREAM, 0))'

# Bypasses found in review: networking, launching, IPC, and code loading that
# leave no denylisted symbol.
build datacontents 'import Foundation
print((try? Data(contentsOf: URL(string: "https://example.com")!))?.count as Any)'
build lsopen 'import Foundation
import CoreServices
print(LSOpenCFURLRef(URL(string: "https://example.com")! as CFURL, nil))'
build openfile 'import AppKit
print(NSWorkspace.shared.openFile("/Applications/Safari.app"))'
build aesend 'import Carbon
var e = AppleEvent(); print(AESendMessage(&e, nil, AESendMode(kAENoReply), kAEDefaultTimeout))'
build xpcconn 'import XPC
print(xpc_connection_create_mach_service("com.example", nil, 0))'
build dnsquery 'import dnssd
var ref: DNSServiceRef?
print(DNSServiceQueryRecord(&ref, 0, 0, "example.com", UInt16(kDNSServiceType_TXT), UInt16(kDNSServiceClass_IN), { _,_,_,_,_,_,_,_,_,_,_ in }, nil))'
build cfbundle 'import Foundation
let b = CFBundleCreate(nil, URL(fileURLWithPath: "/tmp/x.bundle") as CFURL)!
print(CFBundleLoadExecutable(b), CFBundleGetFunctionPointerForName(b, "f" as CFString) as Any)'
build classname 'import Foundation
print(NSClassFromString(["NS", "Task"].joined()) as Any)'
printf 'not a binary\n' > "$WORK/notmacho"

expect clean 0
expect net 1
expect spawn 1
expect dyld 1
expect sock 1
expect datacontents 1
expect lsopen 1
expect openfile 1
expect aesend 1
expect xpcconn 1
expect dnsquery 1
expect cfbundle 1
expect classname 1
expect notmacho 1

[ "$fails" -eq 0 ] && echo "check-binary-test: all passed" || { echo "check-binary-test: $fails failed"; exit 1; }
