import Carbon.HIToolbox
import Cocoa

// The background process: Ctrl+Left/Right hotkey and 3-finger swipe, both feeding
// switchSpace(right:). Ported from noswoosh (see AUDIT.md: "Accessibility wait",
// "yank guard", "hotkey", "swipe tap").

let spacehopVersion = "0.1.0"

func logLine(_ message: String) {
    FileHandle.standardError.write("spacehop: \(message)\n".data(using: .utf8)!)
}

// MARK: - Accessibility wait

// macOS checks Accessibility trust once at process start, so a grant made while
// we run doesn't apply. Poll, and exit once trusted: the LaunchAgent's KeepAlive
// starts a fresh process that has the grant.
func waitForAccessibilityIfNeeded() {
    let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
    guard !AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary) else { return }
    logLine("waiting for Accessibility permission (System Settings > Privacy & Security > Accessibility)")
    Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
        guard AXIsProcessTrusted() else { return }
        logLine(getppid() == 1 ? "Accessibility granted, restarting to apply it"
                               : "Accessibility granted, restart spacehop to apply it")
        exit(0)
    }
}

// MARK: - Empty-desktop yank guard

// Landing on a Space with no normal windows makes macOS activate some other app.
// If that app's window is on another Space, the Dock follows it there ~400 ms
// later and you are pulled off the Space you chose. This is macOS behaviour;
// native switching does it too. Taking activation ourselves the moment we land
// on an empty Space stops it: we have no windows, so there is nothing to follow.
// Needs activation policy .accessory (a .prohibited app cannot become active).
// Upstream measured 8/8 yanked without it, 0/8 with it, on macOS 27.0.
func installYankGuard() {
    NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.activeSpaceDidChangeNotification,
        object: nil, queue: .main
    ) { _ in
        if !spaceHasWindows(activeSpaceID()) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Ctrl+Left / Ctrl+Right hotkey

// Carbon hotkeys: macOS delivers only these two key combinations to us. No
// other keystroke ever reaches this process.
let hotKeySignature = OSType(0x5348_4F50) // 'SHOP'

func installHotKeys() {
    var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                  eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
        var hotKeyID = EventHotKeyID()
        GetEventParameter(event, EventParamName(kEventParamDirectObject),
                          EventParamType(typeEventHotKeyID), nil,
                          MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
        guard hotKeyID.signature == hotKeySignature else { return OSStatus(eventNotHandledErr) }
        switchSpace(right: hotKeyID.id == 2)
        return noErr
    }, 1, &eventType, nil, nil)

    for (id, keyCode) in [(UInt32(1), UInt32(kVK_LeftArrow)), (UInt32(2), UInt32(kVK_RightArrow))] {
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: hotKeySignature, id: id)
        let status = RegisterEventHotKey(keyCode, UInt32(controlKey), hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            logLine("could not register Ctrl+arrow hotkey (status \(status))")
        }
    }
}

// MARK: - 3-finger swipe

// A real swipe's direction is the sign of its progress (on .changed) or velocity
// (on .ended): positive is right, on macOS 26 and 27, with Natural scrolling on
// or off (measured upstream on 27.0). This is deliberately NOT the sign we post
// on 27 (see makeAugmentedDockEvent): reading and posting use opposite
// conventions there. Do not "tidy" them to match; flipping this side inverts
// every trackpad swipe.
func isRightSwipe(_ direction: Double) -> Bool {
    direction > 0
}

var swipeTracking = false
var swipeFired = false
var swipeTap: CFMachPort?

func resetSwipeState() { swipeTracking = false; swipeFired = false }

// Sees only gesture (29) and Dock-control (30) events; never keys or the mouse.
// Horizontal Dock swipes are swallowed and replaced by the instant switch.
// Vertical swipes (Mission Control, App Exposé) and everything else pass through.
let swipeCallback: CGEventTapCallBack = { _, type, ev, _ in
    let pass = Unmanaged.passUnretained(ev)

    if type == .tapDisabledByUserInput || type == .tapDisabledByTimeout {
        resetSwipeState()
        if AXIsProcessTrusted(), let t = swipeTap { CGEvent.tapEnable(tap: t, enable: true) }
        return pass
    }

    let et = ev.getIntegerValueField(fieldCGSEventType)

    // Our own synthetic events: let them through.
    if (et == kCGSEventDockControl || et == kCGSEventGesture)
        && ev.getIntegerValueField(.eventSourceUserData) == spacehopEventTag {
        return pass
    }

    if et == kCGSEventDockControl
        && ev.getIntegerValueField(fieldGestureHIDType) == kIOHIDEventTypeDockSwipe
        && ev.getIntegerValueField(fieldSwipeMotion) == kCGGestureMotionHorizontal {
        switch ev.getIntegerValueField(fieldGesturePhase) {
        case GesturePhase.began.rawValue:
            swipeTracking = true; swipeFired = false
            return nil
        case GesturePhase.changed.rawValue:
            if swipeTracking && !swipeFired {
                let p = ev.getDoubleValueField(fieldSwipeProgress)
                if p != 0 { swipeFired = true; switchSpace(right: isRightSwipe(p)) }
            }
            return swipeTracking ? nil : pass
        case GesturePhase.ended.rawValue:
            let wasTracking = swipeTracking
            if swipeTracking && !swipeFired {
                let v = ev.getDoubleValueField(fieldSwipeVelocityX)
                if v != 0 { switchSpace(right: isRightSwipe(v)) }
            }
            resetSwipeState()
            // On 27, let the real end event through with its motion zeroed so the
            // Dock can close its own gesture state after our switch.
            if needsAugmentation && wasTracking {
                ev.setDoubleValueField(fieldSwipeVelocityX, value: 0)
                ev.setDoubleValueField(fieldSwipeVelocityY, value: 0)
                ev.setDoubleValueField(fieldSwipeProgress, value: 0)
                return pass
            }
            return wasTracking ? nil : pass
        case GesturePhase.cancelled.rawValue:
            resetSwipeState()
            return nil
        default:
            return swipeTracking ? nil : pass
        }
    }

    // Companion gesture events of a swipe we are replacing.
    if et == kCGSEventGesture && swipeTracking { return nil }
    return pass
}

func installSwipeTap() {
    let mask = (CGEventMask(1) << kCGSEventGesture) | (CGEventMask(1) << kCGSEventDockControl)
    guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
                                      options: .defaultTap, eventsOfInterest: mask,
                                      callback: swipeCallback, userInfo: nil) else {
        // Fails until Accessibility is granted; the wait above restarts us then.
        logLine("could not create swipe event tap (Accessibility not granted yet?)")
        return
    }
    swipeTap = tap
    let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
    CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
    CGEvent.tapEnable(tap: tap, enable: true)
    // macOS can disable a tap under load without telling the callback. Check every
    // 5 s so swipes don't silently stop until the next restart.
    Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
        if AXIsProcessTrusted(), !CGEvent.tapIsEnabled(tap: tap) {
            CGEvent.tapEnable(tap: tap, enable: true)
            logLine("re-enabled swipe event tap")
        }
    }
}

// MARK: - Entry

func runDaemon() -> Never {
    waitForAccessibilityIfNeeded()
    let app = NSApplication.shared
    // No Dock icon, no Cmd-Tab entry, but still able to become active (yank guard).
    app.setActivationPolicy(.accessory)
    installYankGuard()
    installHotKeys()
    installSwipeTap()
    logLine("running (spacehop \(spacehopVersion), macOS \(macOSMajor))")
    app.run()
    exit(0)
}
