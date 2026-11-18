# spacehop

Instant switching between macOS desktops (Spaces), with no slide animation.
Ctrl+Left / Ctrl+Right, or a horizontal three-finger swipe, moves one desktop
at once.

## Why this exists

Tools that do this need Accessibility permission, which lets an app watch and
send input. spacehop exists so that permission goes only to code its owner has
read line by line. It is a port of
[noswoosh](https://github.com/mmathys/noswoosh), and every line taken from
another project is recorded in [`AUDIT.md`](AUDIT.md): where it came from, what
it does, and what was changed.

What spacehop does not have, by design:

- No network code of any kind, no updater, no telemetry.
- No launching of other programs, no loading of code at runtime.
- No settings read from environment variables or files.
- No keyboard tap: macOS delivers only Ctrl+Left/Right to its code.
- No third-party dependencies, no prebuilt downloads, no CI.

Every build runs [`scripts/check-binary.sh`](scripts/check-binary.sh). It fails
the build if the binary links a library outside a short list of Apple frameworks,
imports any C/Objective-C function not in
[`scripts/allowed-imports.txt`](scripts/allowed-imports.txt), or uses a URL.
`tests/check-binary-test.sh` proves it rejects 13 kinds of networking,
app-launching, inter-process, and code-loading programs. A static scan catches
ordinary API use, not a deliberately hostile author; that's what `AUDIT.md` is for.

## Requirements

- macOS 26.6 or newer (developed on macOS 27.2.1, Apple silicon).
- Xcode Command Line Tools (`xcode-select --install`).

## Install

```bash
scripts/install.sh
```

This builds and scans the binary, copies it to `~/.local/bin/spacehop`, starts
it at login, and turns off the system's animated Ctrl+arrow shortcuts. Then
allow it in System Settings > Privacy & Security > Accessibility. It restarts
itself once allowed.

To update, pull and run `scripts/install.sh` again, then remove "spacehop" from
the Accessibility list and allow it again. Each build is signed ad-hoc, so the
permission belongs to that exact build and nothing else can inherit it.

## Uninstall

```bash
scripts/uninstall.sh
```

Removes everything the install made and turns the system shortcuts back on.
Remove "spacehop" from the Accessibility list yourself afterwards.

## Other commands

```
spacehop left | right     switch once
spacehop setup | teardown turn the system Ctrl+arrow shortcuts off / on
spacehop version
```

## Tests

```bash
tests/check-binary-test.sh   # the scanner rejects network/launch/dlopen binaries
scripts/build.sh --test      # payload layout, edge clamp, natural-scrolling sign
```

## How it works

About 600 lines of Swift, no dependencies. If you want the same thing in your
own app, read in this order:

| File | What it does |
|------|--------------|
| [`Sources/Swipe.swift`](Sources/Swipe.swift) | The core trick. Posts a synthetic Dock-swipe gesture (began/changed/ended) with a huge fling velocity, so the Dock commits the switch in one frame. On macOS 27+ each event also needs a raw IOHID payload appended to its serialized form (`augment`). Also: edge clamping, natural-scrolling sign, and predicting the current Space during rapid presses. |
| [`Sources/Spaces.swift`](Sources/Spaces.swift) | Finds the current Space and the list of Spaces on the display under the cursor, via private SkyLight calls (`SLSCopyManagedDisplaySpaces`, `SLSGetActiveSpace`). |
| [`Sources/Daemon.swift`](Sources/Daemon.swift) | Inputs. Carbon `RegisterEventHotKey` for Ctrl+Left/Right; a `CGEventTap` limited to gesture events that swallows real horizontal three-finger swipes and replaces them with the instant switch; the "yank guard" that stops macOS from jumping back to the app you left when you land on an empty Space. |
| [`Sources/SystemShortcuts.swift`](Sources/SystemShortcuts.swift) | Turns the system's own animated Ctrl+arrow shortcuts off/on so they don't fire too. |
| [`Sources/main.swift`](Sources/main.swift) | CLI entry point. |

Whatever triggers a switch, it ends in `switchSpace(right:)`. Posting events and
the event tap both need Accessibility permission. Comments in the code record
which numbers were measured on which macOS version; [`AUDIT.md`](AUDIT.md)
explains each piece in more depth.

## Fragility

spacehop relies on undocumented parts of macOS: private SkyLight functions and
private event fields, plus a payload format macOS 27 started requiring. There is
no public API for instant switching. Any macOS update can break it. When it
breaks, nothing unsafe happens; switching just stops working.

## Credits

noswoosh (Max Mathys), InstantSpaceSwitcher (jurplel), and iss (joshuarli). Licence notices in [`NOTICE`](NOTICE).
