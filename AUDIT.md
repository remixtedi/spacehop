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
ApplicationServices, CoreFoundation, CoreGraphics, CoreServices, ColorSync, SkyLight) and
imports no networking, process-launch, or dynamic-loading symbols or selectors.
`tests/check-binary-test.sh` proves it rejects binaries using `URLSession`,
`Process`, `dlopen`, and `socket`, and accepts a clean AppKit binary.
Private APIs: none.
Verdict: OK.
Notes: the Swift compiler auto-links weak overlay libraries such as
`libswiftXPC` and `libswiftMetal` even when they are unused. They are allowed by
the `libswift*` rule; actual use of networking or launching through them is
still caught by the symbol and string checks.
ColorSync is allowed because Apple implements
`CGDisplayCreateUUIDFromDisplayID` (used by Space lookup) in it; it is a
colour-management framework with no networking or launching role.

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

## Space lookup

Source: mmathys/noswoosh@14051ab `noswoosh.swift` L86-L167, L171-L183, L504-L516 (file `Sources/Spaces.swift`).
Does: asks the window server for the list of Spaces per display and which one is
showing; picks the display under the mouse cursor when there are several;
checks whether a Space has any normal windows; reads the macOS major version
from `kern.osproductversion`. Read-only, no side effects.
Private APIs: `SLSMainConnectionID`, `SLSCopyManagedDisplaySpaces`,
`SLSGetActiveSpace`, `SLSCopySpacesForWindows` (SkyLight, linked directly).
Public APIs: `CGGetDisplaysWithPoint`, `CGDisplayCreateUUIDFromDisplayID`,
`CGWindowListCopyWindowInfo` (window numbers and layers only; no titles,
no contents), `sysctlbyname`.
Verdict: changed.
Changes:
- `NOSWOOSH_FORCE_AUGMENT` environment override (L185-L192) removed;
  `needsAugmentation` is `macOSMajor >= 27`.
- Forced cast `as! [[String: Any]]` on the SkyLight result replaced with a
  `guard` that returns nil, so an unexpected result can't crash the daemon.
- Added `activeSpaceID()` wrapper so the daemon doesn't touch `cid` directly.
- Comments shortened; references to upstream issue numbers removed.

## macOS 26 swipe

Source: mmathys/noswoosh@14051ab `noswoosh.swift` L216-L271 (file `Sources/Swipe.swift`).
Does: builds one synthetic Dock-swipe `CGEvent` per gesture phase (began,
changed, ended) with progress ±1e-4 and velocity ±2000, tags it, and posts it to
the session event stream. The Dock treats it as a finished three-finger swipe
with nothing left to animate.
Private APIs: undocumented CGEvent fields 55 (event type), 110 (HID type),
123 (motion), 124 (progress), 129/130 (velocity), 132 (phase); event types
29 (gesture) and 30 (Dock control); HID type 23 (Dock swipe).
Verdict: OK.
Changes: tag constant `noswooshEventTag` 0x4E535753 ('NSWS') → `spacehopEventTag`
0x5348_4F50 ('SHOP').

## macOS 27 payload

Source: mmathys/noswoosh@14051ab `noswoosh.swift` L195-L214, L273-L408 (file `Sources/Swipe.swift`).
Does: on macOS 27 the Dock only accepts a synthetic swipe whose serialized form
carries a raw IOHID payload under field 4205. `generateIOHIDPayload` writes a
28-byte queue header, a 40-byte fluid-touch gesture record, and on motion/end a
28-byte velocity record, all little-endian, from the event's own fields only.
`augment` appends that to the serialized event and rebuilds the event. Each
Dock event is posted with a companion gesture event (type 29). Progress ±0.1
(upstream measured 1e-4 → black landings on 27.0.1; ≥0.03 → none), fling
±9999 on the end phase, sign flipped when Natural scrolling is off.
Reads one system preference: `com.apple.swipescrolldirection` (read-only).
Private APIs: as above, plus fields 115 (swipe mask), 125/126 (position), 4205
(raw IOHID payload), and the serialized-event format (version 2 header).
Verdict: changed.
Changes:
- Natural-scrolling sign split into a pure `postedSwipeSign(naturalScrolling:)`
  (unit-tested) plus a cached `postedSign`.
- Tag renamed as above.
Tests: `test_fixed1616`, `test_payload_layout` (sizes 96/68, record sizes and
types, phase byte), `test_augment_header`, `test_postedSign_naturalOff`.

## Switch core

Source: mmathys/noswoosh@14051ab `noswoosh.swift` L410-L467 (file `Sources/Swipe.swift`).
Does: `switchSpace(right:)` looks up the Space list, uses its own prediction
for 0.25 s (0.4 s on 27) after a switch so rapid presses aren't blocked by a
stale list, stops at the first/last Space, then posts the full gesture. On 27
all three events are built before any is posted, so a half gesture is never sent.
Private APIs: via Space lookup and the swipe functions above.
Verdict: changed.
Changes: edge check extracted to `nextIndex(current:count:right:)` (unit-tested,
`test_clamp_and_prediction`); behaviour identical. A code-only diff against
upstream (comments and whitespace stripped) shows only these renames and the
extraction.

## CLI

Source: mmathys/noswoosh@14051ab `noswoosh.swift` L582-L627, reduced (file `Sources/main.swift`).
Does: `spacehop left|right` switches once and exits after 0.15 s so the posted
events flush; `spacehop version` prints the version; anything else prints usage
and exits 1.
Private APIs: none directly.
Verdict: changed.
Changes: `list` subcommand dropped (convenience only). `setup`/`teardown` are
added back in "System shortcuts" without the `defaults`/`killall` calls.

## System shortcuts

Source: mmathys/noswoosh@14051ab `noswoosh.swift` L64-L84, L597-L619 (file `Sources/SystemShortcuts.swift`, `setup`/`teardown` in `Sources/main.swift`).
Does: `spacehop setup` turns off macOS's own "Move left/right a space" shortcuts
(symbolic hotkeys 79/81, Ctrl+Left/Right), both for the running session and in
`com.apple.symbolichotkeys` for future logins, so Ctrl+arrow reaches spacehop.
`spacehop teardown` turns them back on.
Private APIs: `SLSSetSymbolicHotKeyEnabled` (SkyLight).
Verdict: changed.
Changes:
- `dlopen`/`dlsym` lookup of `SLSSetSymbolicHotKeyEnabled` replaced with a direct
  `@_silgen_name` declaration (the binary already links SkyLight), so the
  scanner can forbid `dlopen`/`dlsym` outright.
- `/usr/bin/defaults write … -dict-add` replaced with `CFPreferencesCopyValue` /
  `CFPreferencesSetValue` that edits only entries 79 and 81 and keeps a binding
  the user changed. No program is launched.
- Legacy cleanup of `com.apple.dock workspaces-auto-swoosh` and `killall Dock`
  (L599-L608) dropped: spacehop never sets that preference.
Tested on this Mac (macOS 27.2.1): setup → 79/81 `enabled=false`; teardown twice
→ `enabled=true`, no error; all other hotkey entries identical before and after.
Side effect: entries 79/81 gain an explicit `value` with the macOS default
binding (`[65535, 123|124, 8650752]`, type `standard`) if they had none.
