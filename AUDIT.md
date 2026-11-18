# Audit log

Every line in spacehop that came from another project is listed here: where it
came from, what it does, which undocumented Apple internals it touches, the
verdict after reading it, and what was changed. Code written fresh for spacehop
is noted as such.

Upstream snapshots audited:

- noswoosh: `mmathys/noswoosh@14051ab58444c6868f603bee9a4daab12f9f6255`, file `noswoosh.swift`
- Interspace: `cnrad/interspace@87c1c34672be921da33486ea91eb6cc0c84ad544`, file `scripts/setup-signing.sh` (ported, later removed; see "Signing (no key)")

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

Source: written for spacehop (`scripts/check-binary.sh`, `scripts/allowed-imports.txt`,
`scripts/build.sh`, `tests/check-binary-test.sh`).
Does: every build fails unless
1. the file is Mach-O and `otool`, `nm`, `strings` all succeed;
2. every linked library is on a short allowlist (libSystem, libobjc, Swift
   runtime overlays, Foundation, AppKit, Cocoa, Carbon, ApplicationServices,
   CoreFoundation, CoreGraphics, CoreServices, ColorSync, SkyLight);
3. every imported C/Objective-C symbol is listed in `scripts/allowed-imports.txt`
   (an exact allowlist: anything new fails until someone adds it on purpose);
4. no Swift symbol uses Foundation's `URL` type (spacehop uses none, and every
   Swift fetch/open/bundle-load API takes one);
5. no denylisted selector/class string appears (`URLSession`, `NSTask`,
   `openURL:`, `openFile`, `launchApplication`, `NSXPCConnection`, …).
`tests/check-binary-test.sh` builds the real program (must pass) and 13 hostile
programs that must fail: `URLSession`, `Process`, `dlopen`, `socket`,
`Data(contentsOf: https URL)`, `LSOpenCFURLRef`, `NSWorkspace.openFile`,
`AESendMessage`, `xpc_connection_create_mach_service`, `DNSServiceQueryRecord`,
`CFBundleLoadExecutable`, `NSClassFromString` with a runtime-built name, and a
non-Mach-O file.
Private APIs: none.
Verdict: OK.
Limits: a static scan catches ordinary API use. It cannot stop a deliberately
hostile author (raw system calls, code hidden in data); that is what reading
every line, recorded below, is for.
Notes:
- Swift auto-links weak overlay libraries such as `libswiftXPC` and
  `libswiftMetal` even when unused. The `libswift*` rule allows them; any actual
  use of an API they wrap shows up as a new import and fails check 3.
- ColorSync is allowed because Apple implements `CGDisplayCreateUUIDFromDisplayID`
  (used by Space lookup) in it; it is a colour-management framework.
- Final review (fresh reviewer) found the first version used a denylist and
  missed 9 of the cases above. Replaced with the allowlist; all 9 are now tests.

## Signing (no key)

Source: written for spacehop (`scripts/build.sh`).
Does: signs every build ad-hoc (`codesign --sign -`, identifier
`com.remixtedi.spacehop`). macOS ties the Accessibility grant to that exact
build, so no other binary can inherit it.
Verdict: OK.
History: the first version ported Interspace's `scripts/setup-signing.sh`
(cnrad/interspace@87c1c34, MIT): a self-signed identity in its own keychain,
keychain password stored in `~/.config/spacehop/`. The final review pointed out
that any program running as the user could read that password, sign its own
binary with the same certificate, and inherit spacehop's Accessibility grant.
The owner chose to remove the key entirely. Cost: after each rebuild the user
removes and re-allows spacehop in Accessibility. No Interspace code remains.

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

## Accessibility wait

Source: mmathys/noswoosh@14051ab `noswoosh.swift` L629-L668 (file `Sources/Daemon.swift`, `waitForAccessibilityIfNeeded`).
Does: asks macOS for Accessibility (shows the system prompt once), logs that it
is waiting, polls once a second, and exits when granted so launchd restarts it
with the grant applied.
Private APIs: none (`AXIsProcessTrustedWithOptions`, `AXIsProcessTrusted`).
Verdict: changed.
Changes: the 15-second automatic opening of System Settings (L656-L666, via
`NSWorkspace.open(URL)`) dropped; the system prompt already offers that button.
This also keeps `openURL:` out of the binary, which the scanner forbids.
`log` renamed `logLine`.

## Yank guard

Source: mmathys/noswoosh@14051ab `noswoosh.swift` L469-L555 (file `Sources/Daemon.swift`, `installYankGuard`).
Does: when the visible Space changes to one with no normal windows, spacehop
makes itself the active app (it has no windows or menus, so nothing appears),
which stops macOS from pulling you to another Space to follow some other app.
Private APIs: via `spaceHasWindows` / `activeSpaceID` (Space lookup).
Verdict: changed.
Changes: `NOSWOOSH_FORCE_YANK_GUARD` environment override (L537-L542) removed;
the guard is always on, as upstream defaults to.

## Hotkey

Source: mmathys/noswoosh@14051ab `noswoosh.swift` L680-L700 (file `Sources/Daemon.swift`, `installHotKeys`).
Does: registers exactly Ctrl+Left and Ctrl+Right with Carbon
`RegisterEventHotKey`. macOS delivers only those two combinations to spacehop's
code. There is no keyboard event tap. One caveat, from the yank guard: on an
empty desktop spacehop is briefly the active app, so keys typed there go to
its event queue, where AppKit discards them (it has no windows or menus). No
spacehop code reads them.
Private APIs: none.
Verdict: changed.
Changes: signature `0x5350_5357` ('SPSW') → `0x5348_4F50` ('SHOP'); the handler
now ignores hotkey events whose signature isn't ours.

## Swipe tap

Source: mmathys/noswoosh@14051ab `noswoosh.swift` L557-L580, L702-L795 (file `Sources/Daemon.swift`, `swipeCallback`, `installSwipeTap`).
Does: an event tap that receives only event types 29 (gesture) and 30 (Dock
control), never keys or mouse. A real horizontal 3-finger swipe is swallowed
and replaced by one instant switch; direction from progress sign (changed) or
velocity sign (ended). Vertical swipes and everything else pass through. Our own
tagged events pass through. A 5-second timer re-enables the tap if macOS
disabled it.
Private APIs: event types 29/30 and the undocumented fields listed under
"macOS 26 swipe".
Verdict: changed.
Changes: top-level code wrapped in `installSwipeTap()`; tag renamed. A code-only
diff against upstream shows nothing else.

## Daemon entry

Source: mmathys/noswoosh@14051ab `noswoosh.swift` L670-L678, L797 (file `Sources/Daemon.swift`, `runDaemon`).
Does: sets activation policy `.accessory` (no Dock icon, no Cmd-Tab), installs
the yank guard, hotkeys and swipe tap, runs the app loop.
Verdict: changed.
Changes: added one startup log line (`running (spacehop <version>, macOS <major>)`)
to `~/Library/Logs/spacehop.log`.

## Install and uninstall

Source: layout follows mmathys/noswoosh@14051ab `scripts/install.sh` and
`scripts/uninstall.sh` (files `scripts/install.sh`, `scripts/uninstall.sh`).
Does: install runs `build.sh` (so the scanner always runs), copies the binary to `~/.local/bin/spacehop` as a fresh file, runs
`spacehop setup`, writes and loads a user LaunchAgent
(`com.remixtedi.spacehop`: RunAtLoad, KeepAlive, Interactive, Aqua session
only, stderr to `~/Library/Logs/spacehop.log`). Uninstall reverses all of it and
tells the user to remove the Accessibility entry by hand.
Verdict: changed.
Changes: optional Developer ID signing dropped (ad-hoc always);
`swiftc` invocation moved into `build.sh`; source file no longer copied next to
the binary; uninstall also removes the log; `spacehop setup`
runs only after the LaunchAgent is loaded, so a failed install leaves the system
Ctrl+arrow shortcuts working (upstream ran it before).
Not automated on purpose: removing the Accessibility entry. `tccutil` can't
target a bare binary by ID, and `tccutil reset Accessibility` with no ID would
remove every app's permission.

## Coverage of noswoosh.swift

| Upstream lines | What | Where / outcome |
|---|---|---|
| L1-L48 | header comment, version | rewritten (`main.swift`, `Daemon.swift`) |
| L50-L62 | `runTool` (launches programs) | **dropped** |
| L64-L84 | Ctrl+arrow system shortcuts | changed, `SystemShortcuts.swift` |
| L86-L167 | SkyLight reads, space list | ported, `Spaces.swift` |
| L169-L183 | macOS version | ported, `Spaces.swift` |
| L185-L192 | `NOSWOOSH_FORCE_AUGMENT` env override | **dropped** |
| L195-L214 | natural-scrolling sign | changed, `Swipe.swift` |
| L216-L271 | macOS 26 swipe | ported, `Swipe.swift` |
| L273-L408 | macOS 27 payload | ported, `Swipe.swift` |
| L410-L467 | switch core | changed, `Swipe.swift` |
| L469-L536 | yank guard rationale, `spaceHasWindows` | ported (`Spaces.swift`, `Daemon.swift`) |
| L537-L542 | `NOSWOOSH_FORCE_YANK_GUARD` env override | **dropped** |
| L544-L555 | yank guard | ported, `Daemon.swift` |
| L557-L580 | swipe direction | ported, `Daemon.swift` |
| L582-L586 | CLI dispatch | changed, `main.swift` |
| L587-L591 | `list` | **dropped** |
| L592-L596 | `left` / `right` | ported, `main.swift` |
| L597-L608 | `setup` incl. `defaults delete` + `killall Dock` | changed; legacy cleanup **dropped** |
| L609-L627 | setup message, teardown, version, usage | changed, `main.swift` |
| L629-L655 | log, Accessibility wait | ported, `Daemon.swift` |
| L656-L666 | auto-open System Settings | **dropped** |
| L667-L678 | activation policy, yank-guard switch | changed, `Daemon.swift` |
| L680-L700 | Carbon hotkey | changed, `Daemon.swift` |
| L702-L795 | swipe tap | ported, `Daemon.swift` |
| L797 | `app.run()` | ported, `Daemon.swift` |

Not taken from noswoosh: `AGENTS.md`, `.github/workflows/release.yml`
(signing secrets, Homebrew push), `scripts/landing-check.swift` (screen-recording
test harness), `scripts/make-app-bundle.sh`, `scripts/Info.plist.in`, assets.

## Final binary (spacehop 0.1.0, macOS 27.2.1 arm64)

Linked libraries (`otool -L build/spacehop`):

```
/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight
/usr/lib/libSystem.B.dylib
/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit
/System/Library/Frameworks/ApplicationServices.framework/Versions/A/ApplicationServices
/System/Library/Frameworks/Carbon.framework/Versions/A/Carbon
/System/Library/Frameworks/ColorSync.framework/Versions/A/ColorSync
/System/Library/Frameworks/CoreFoundation.framework/Versions/A/CoreFoundation
/System/Library/Frameworks/CoreGraphics.framework/Versions/A/CoreGraphics
/System/Library/Frameworks/Foundation.framework/Versions/C/Foundation
/usr/lib/libobjc.A.dylib
/usr/lib/swift/libswiftCore.dylib
/usr/lib/swift/libswiftCoreFoundation.dylib
/usr/lib/swift/libswiftCoreImage.dylib
/usr/lib/swift/libswiftDispatch.dylib
/usr/lib/swift/libswiftIOKit.dylib
/usr/lib/swift/libswiftMetal.dylib
/usr/lib/swift/libswiftOSLog.dylib
/usr/lib/swift/libswiftObjectiveC.dylib
/usr/lib/swift/libswiftQuartzCore.dylib
/usr/lib/swift/libswiftSpatial.dylib
/usr/lib/swift/libswiftUniformTypeIdentifiers.dylib
/usr/lib/swift/libswiftXPC.dylib
/usr/lib/swift/libswift_Builtin_float.dylib
/usr/lib/swift/libswiftos.dylib
/usr/lib/swift/libswiftsimd.dylib
```

Imported symbols outside the Swift runtime (`nm -u build/spacehop | grep -v '^_\$s\|^__swift\|^_swift_'`):

```
_AXIsProcessTrusted
_AXIsProcessTrustedWithOptions
_CFMachPortCreateRunLoopSource
_CFPreferencesCopyAppValue
_CFPreferencesCopyValue
_CFPreferencesSetValue
_CFPreferencesSynchronize
_CFRunLoopAddSource
_CFRunLoopGetCurrent
_CFUUIDCreateString
_CGDisplayCreateUUIDFromDisplayID
_CGEventCreate
_CGEventCreateFromData
_CGEventGetDoubleValueField
_CGEventGetIntegerValueField
_CGEventGetLocation
_CGEventGetTimestamp
_CGEventPost
_CGEventSetDoubleValueField
_CGEventSetIntegerValueField
_CGEventTapCreate
_CGEventTapEnable
_CGEventTapIsEnabled
_CGGetDisplaysWithPoint
_CGWindowListCopyWindowInfo
_GetApplicationEventTarget
_GetEventParameter
_InstallEventHandler
_NSApp
_NSWorkspaceActiveSpaceDidChangeNotification
_OBJC_CLASS_$_NSApplication
_OBJC_CLASS_$_NSArray
_OBJC_CLASS_$_NSFileHandle
_OBJC_CLASS_$_NSNumber
_OBJC_CLASS_$_NSOperationQueue
_OBJC_CLASS_$_NSRunLoop
_OBJC_CLASS_$_NSTimer
_OBJC_CLASS_$_NSWorkspace
_RegisterEventHotKey
_SLSCopyManagedDisplaySpaces
_SLSCopySpacesForWindows
_SLSGetActiveSpace
_SLSMainConnectionID
_SLSSetSymbolicHotKeyEnabled
__Block_copy
__Block_release
__NSConcreteStackBlock
___chkstk_darwin
___stack_chk_fail
___stack_chk_guard
_bzero
_exit
_getppid
_kAXTrustedCheckOptionPrompt
_kCFPreferencesAnyApplication
_kCFPreferencesAnyHost
_kCFPreferencesCurrentUser
_kCFRunLoopCommonModes
_kCGWindowLayer
_kCGWindowNumber
_mach_absolute_time
_malloc_size
_memcpy
_memmove
_objc_msgSend
_objc_opt_self
_objc_release
_objc_retain
_objc_retainAutoreleasedReturnValue
_sysctlbyname
```

Scanner:

```
check-binary: OK (build/spacehop)
```
