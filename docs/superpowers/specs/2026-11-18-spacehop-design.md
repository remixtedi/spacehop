# spacehop — design

Instant macOS desktop (Space) switching, owned and audited by remixtedi.

## Intent

The owner wants instant Space switching (no slide animation) but does not trust
young third-party projects with Accessibility access. The fix is ownership: a
copy under the `remixtedi` GitHub account where every line was read before it
went in, nothing can phone home, nothing can fetch or run remote code, and
nothing changes without the owner seeing the diff.

Trust is the product. Features are secondary.

## Goals

- Ctrl+Left / Ctrl+Right and a horizontal 3-finger trackpad swipe switch one
  Space instantly, same behaviour as noswoosh 1.7.7.
- Works on the owner's Mac: macOS 27.2.1, Apple Silicon.
- Every line taken from another project is recorded in `AUDIT.md`: source repo,
  commit, line range, what it does, verdict, and what we changed.
- The build fails if the binary contains networking or process-launching code.
- Accessibility permission survives rebuilds (stable local signing identity).
- Clean uninstall that restores the system Ctrl+arrow shortcuts.

## Non-goals

- Animations, menu bar UI, settings window, configurable hotkeys.
- Prebuilt downloads, releases, Homebrew, notarization.
- Mission Control / vertical swipe handling (passes through untouched).

## Anti-goals (failure even if it "works")

- Any network code, updater, telemetry, or crash reporter.
- Any code that launches other programs at runtime.
- Reading environment variables or files that change behaviour (hidden switches).
- Seeing keystrokes beyond Ctrl+Left / Ctrl+Right.
- Third-party dependencies, package managers, or CI that holds secrets.
- Code nobody on this repo has read.

## Constraints

- Relies on undocumented Apple internals (SkyLight `SLS*` calls, private
  CGEvent fields 55/110/115/123–132, the macOS 27 raw IOHID payload in field
  4205). These can break on any macOS update; there is no public API for this.
- Needs Accessibility permission (event tap + posting events). Not Screen
  Recording.
- No Apple Developer ID: signing is a self-signed identity made on this Mac.
- Licences: noswoosh (MIT, Max Mathys), InstantSpaceSwitcher (MIT, jurplel) for
  the synthetic-swipe technique, joshuarli/iss (0BSD, no notice required, credited
  anyway) for the macOS 27 payload layout, Interspace (MIT, cnrad) for the
  signing script. Their notices go in `NOTICE`.

## Approaches

| | Approach | Trade-off |
|---|---|---|
| A | Fork noswoosh as-is at `14051ab` | Fast, but carries release CI with secrets, Homebrew bump, test harness, 300-line AGENTS.md. More to trust, nothing gained. |
| **B (chosen)** | New repo; port noswoosh.swift section by section with audit notes, strip what isn't needed, add hardening | Slower; result is small, owned, and machine-checked. |
| C | Rewrite from scratch using only the technique | Private-API code ends up near-identical anyway; more new bugs, no trust gain. |

Owner picked B.

## Design

### Repo layout

```
spacehop/
  spacehop.swift        the whole program (port of noswoosh.swift)
  scripts/
    setup-signing.sh    one-time local code-signing identity (from Interspace, audited)
    build.sh            compile, sign, run check-binary.sh; fails if check fails
    check-binary.sh     denylist scan of the built binary
    install.sh          build + install to ~/.local/bin + LaunchAgent
    uninstall.sh        reverse everything
  AUDIT.md              line-provenance and verdict log
  LICENSE / NOTICE      MIT for our code + upstream notices
  README.md             what it is, install, uninstall, permissions
```

### What is kept from noswoosh.swift (behaviour unchanged)

- Space list lookup via `SLSCopyManagedDisplaySpaces` / `SLSGetActiveSpace`,
  cursor-display routing for multi-monitor.
- Synthetic Dock-swipe: pre-27 path and macOS 27 augmented path (IOHID payload,
  companion events, progress 0.1, ±9999 fling, natural-scrolling sign).
- Event tag so our own synthetic events pass back through our tap.
- Edge clamp + short prediction window for rapid presses.
- Empty-desktop yank guard (activate self on landing on a windowless Space).
- Ctrl+arrow via Carbon `RegisterEventHotKey` (only those two combos reach us).
- 3-finger swipe tap on event types 29/30 only (no keyboard event tap).
- Accessibility wait loop that exits once trusted so launchd restarts us.

### What is removed or changed (hardening)

- `dlopen`/`dlsym` of `SLSSetSymbolicHotKeyEnabled`: replaced with a direct
  `@_silgen_name` declaration (binary already links SkyLight), so `dlopen`/`dlsym`
  can go on the denylist. *(builder's call)*
- `NOSWOOSH_FORCE_AUGMENT` and `NOSWOOSH_FORCE_YANK_GUARD` env overrides: removed.
  Decision is OS version only; yank guard always on.
- `runTool` / `Process`: removed. Ctrl+arrow system shortcuts are written with
  `CFPreferencesSetValue` on `com.apple.symbolichotkeys` instead of shelling to
  `defaults`. The legacy `workspaces-auto-swoosh` cleanup and `killall Dock` are
  dropped (we never set that pref).
- Auto-opening System Settings after 15 s: removed. The system Accessibility
  prompt already offers that button; we only log.
- CLI keeps `left`, `right`, `setup`, `teardown`, `version`. `list` dropped
  (convenience only).
- Names: binary `spacehop`, event tag and hotkey signature changed to our own
  constants, LaunchAgent label `com.remixtedi.spacehop`.

### Binary check (`check-binary.sh`, run by every build)

Fails the build if the compiled binary:
- imports networking symbols (`nm -u`): `socket`, `connect`, `getaddrinfo`,
  `CFSocket*`, `CFStream*`, `nw_*`, `CFNetwork`/`Network` framework linkage
  (`otool -L`), or
- imports dynamic-loading symbols: `dlopen`, `dlsym`, or
- imports process-launch symbols: `posix_spawn*`, `execv*`, `execl*`, `fork`,
  `system`, `popen`, or
- contains Objective-C selectors / class names for networking or launching
  (`strings`): `NSURLSession`, `URLSession`, `NSURLConnection`, `NSTask`,
  `openURL:`, `launchApplication`, `openApplicationAtURL`.

Frameworks linked must be exactly an allowlist (Foundation, AppKit/Cocoa,
Carbon, ApplicationServices, CoreFoundation, CoreGraphics, SkyLight, Swift
runtime); anything else fails.

### Signing

`setup-signing.sh` creates a self-signed code-signing identity in its own
keychain (`~/Library/Keychains/spacehop-signing.keychain-db`, password in
`~/.config/spacehop/`, mode 600). The login keychain is not touched.
`build.sh` signs with it so the Accessibility grant survives rebuilds.

### Install / run

`install.sh`: build (which runs the check), copy to `~/.local/bin/spacehop`,
run `spacehop setup`, write and load LaunchAgent (RunAtLoad, KeepAlive,
Aqua session, stderr to `~/Library/Logs/spacehop.log`). The owner grants
Accessibility once.

`uninstall.sh`: unload and delete LaunchAgent, `spacehop teardown`, delete
binary, delete signing keychain and `~/.config/spacehop`, then print the one
manual step: remove `spacehop` from System Settings > Privacy & Security >
Accessibility. *(builder's call: `tccutil` can't target a bare binary by ID, and
`tccutil reset Accessibility` with no ID would wipe every app's grant.)*

No GitHub Actions. All checks run locally in `build.sh`.

### Build order and stop rule *(builder's call)*

The technique was measured upstream on 27.0 / 27.0.1; this Mac runs 27.2.1.
So the first ported sections are the switch core (space lookup, both swipe
paths, `left`/`right` CLI). That is our own audited code, so nothing
unreviewed runs. Test `spacehop left` / `right` on this Mac before porting the
rest. If the switch doesn't work on 27.2.1, stop and report to the owner. New
reverse-engineering is out of scope unless the owner says otherwise.

### Audit process

Port in small commits, one logical section per commit (e.g. "space lookup",
"pre-27 swipe", "27 payload", "yank guard", "hotkey", "swipe tap", "CLI").
Each commit adds the matching `AUDIT.md` entry:

```
## <section>
Source: mmathys/noswoosh@14051ab noswoosh.swift L<a>-L<b>
Does: <plain description>
Private APIs: <list>
Verdict: OK / changed
Changes: <what and why>
```

Commits are authored by the owner's git identity with no AI attribution.

**Review and publishing (owner decided):** all section commits are made
locally. The owner reviews the full diff and `AUDIT.md` once at the end.
Nothing leaves the Mac before that approval. After approval, create
`remixtedi/spacehop` as a **private** GitHub repo with `gh` (account
`remixtedi`) and push.

### Verification

- `check-binary.sh` passes; a deliberately added `URLSession` line makes it fail
  (one-time sanity test of the checker, not committed).
- Manual on the owner's Mac: Ctrl+←/→ switches instantly; 3-finger swipe
  switches instantly; vertical swipes still open Mission Control; edge Space
  doesn't bounce; landing on an empty desktop doesn't yank; uninstall restores
  the animated Ctrl+arrow shortcuts.
- `nm -u` and `otool -L` output pasted into `AUDIT.md` for the release commit.

## Left to the builder

- Exact denylist tuning if Swift runtime pulls in a benign symbol that matches.
- Exact wording of README and log messages.

## Changes after approval

- 2026-11-18, owner decision after final review: no signing key. Builds are
  signed ad-hoc; the "Accessibility survives rebuilds" goal is dropped because
  the stored keychain password let any same-user program inherit the grant.
  `setup-signing.sh` removed.
- 2026-11-18, final review: binary scanner switched from a denylist to an exact
  import allowlist (`scripts/allowed-imports.txt`).
