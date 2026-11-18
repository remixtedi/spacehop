# Audit log

Every line in spacehop that came from another project is listed here: where it
came from, what it does, which undocumented Apple internals it touches, the
verdict after reading it, and what was changed. Code written fresh for spacehop
is noted as such.

Upstream snapshots audited:

- noswoosh: `mmathys/noswoosh@14051ab58444c6868f603bee9a4daab12f9f6255`, file `noswoosh.swift`
- Interspace: `cnrad/interspace@87c1c34672be921da33486ea91eb6cc0c84ad544`, file `scripts/setup-signing.sh`

Entry format:

```
## <section>
Source: <repo>@<commit> <file> L<a>-L<b>
Does: <plain description>
Private APIs: <list, or none>
Verdict: OK / changed
Changes: <what and why>
```

---

## Binary scanner and build script

Source: written for spacehop (`scripts/check-binary.sh`, `scripts/build.sh`, `tests/check-binary-test.sh`).
Does: every build fails unless the binary links only allowlisted libraries
(libSystem, libobjc, Swift runtime overlays, Foundation, AppKit, Cocoa, Carbon,
ApplicationServices, CoreFoundation, CoreGraphics, CoreServices, SkyLight) and
imports no networking, process-launch, or dynamic-loading symbols or selectors.
`tests/check-binary-test.sh` proves it rejects binaries using `URLSession`,
`Process`, `dlopen`, and `socket`, and accepts a clean AppKit binary.
Private APIs: none.
Verdict: OK.
Notes: the Swift compiler auto-links weak overlay libraries such as
`libswiftXPC` and `libswiftMetal` even when they are unused. They are allowed by
the `libswift*` rule; actual use of networking or launching through them is
still caught by the symbol and string checks.

## Local signing identity

Source: cnrad/interspace@87c1c34 `scripts/setup-signing.sh` L1-L57.
Does: one time, makes a self-signed RSA-2048 code-signing certificate
(CN `spacehop local signing`, codeSigning EKU only, not a CA, 10 years) with the
system LibreSSL, imports it into a new keychain
`~/Library/Keychains/spacehop-signing.keychain-db`, and stores that keychain's
random password in `~/.config/spacehop/signing-keychain-password` (umask 077).
Only `/usr/bin/codesign` may use the key. The login keychain is not touched.
Temp files are removed on exit. Nothing leaves the Mac.
Private APIs: none.
Verdict: OK.
Changes: names and paths only (`interspace` → `spacehop`), comments updated.
`diff` against upstream shows no other change.
