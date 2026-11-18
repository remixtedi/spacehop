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
- No keyboard tap: macOS delivers only Ctrl+Left/Right to it.
- No third-party dependencies, no prebuilt downloads, no CI.

Every build runs [`scripts/check-binary.sh`](scripts/check-binary.sh), which
fails the build if the binary links anything outside a short list of Apple
frameworks or imports any networking, process-launch, or dynamic-loading
function. `tests/check-binary-test.sh` proves the scanner catches those.

## Requirements

- macOS 26.6 or newer (developed on macOS 27.2.1, Apple silicon).
- Xcode Command Line Tools (`xcode-select --install`).

## Install

```bash
scripts/install.sh
```

This makes a local code-signing identity (one time, in its own keychain), builds
and scans the binary, copies it to `~/.local/bin/spacehop`, turns off the
system's animated Ctrl+arrow shortcuts, and starts spacehop at login. Then allow
it in System Settings > Privacy & Security > Accessibility. It restarts itself
once allowed.

Run `scripts/install.sh` again after pulling changes.

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

## Fragility

spacehop relies on undocumented parts of macOS: private SkyLight functions and
private event fields, plus a payload format macOS 27 started requiring. There is
no public API for instant switching. Any macOS update can break it. When it
breaks, nothing unsafe happens; switching just stops working.

## Credits

noswoosh (Max Mathys), InstantSpaceSwitcher (jurplel), Interspace (cnrad), and
iss (joshuarli). Licence notices in [`NOTICE`](NOTICE).
