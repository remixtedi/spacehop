import Cocoa

// Switches one Space by posting a synthetic Dock-swipe gesture that commits
// instantly. Ported from noswoosh (see AUDIT.md: "macOS 26 swipe",
// "macOS 27 payload", "switch core"). The technique comes from
// InstantSpaceSwitcher; the macOS 27 payload layout from joshuarli/iss.
//
// The switch goes through the Dock's own gesture pipeline, so the Dock stays the
// only owner of the Spaces model. The gesture has almost no distance to travel,
// so there is nothing to animate.

// MARK: - Undocumented CGEvent fields

func field(_ n: UInt32) -> CGEventField { unsafeBitCast(n, to: CGEventField.self) }
let fieldCGSEventType   = field(55)
let fieldGestureHIDType = field(110)
let fieldSwipeMask      = field(115)   // 27 payload
let fieldSwipeMotion    = field(123)
let fieldSwipeProgress  = field(124)
let fieldSwipePositionX = field(125)   // 27 payload
let fieldSwipePositionY = field(126)   // 27 payload
let fieldSwipeVelocityX = field(129)
let fieldSwipeVelocityY = field(130)
let fieldGesturePhase   = field(132)

let kCGSEventGesture: Int64 = 29
let kCGSEventDockControl: Int64 = 30
let kIOHIDEventTypeDockSwipe: Int64 = 23
let kCGGestureMotionHorizontal: Int64 = 1
let kRawIOHIDPayloadTag: Int = 4205    // 0x106D: CGEvent field carrying the payload
let gestureVelocity = 2000.0

enum GesturePhase: Int64 { case began = 1, changed = 2, ended = 4, cancelled = 8 }

// Our own synthetic events come back through our own event tap. They carry this
// tag in the user-data field so the tap lets them through. Real trackpad
// gestures carry 0 there.
let spacehopEventTag: Int64 = 0x5348_4F50 // 'SHOP'

// MARK: - Natural scrolling

// On macOS 27 the Dock reads a posted swipe relative to "Natural scrolling":
// with it off, the same posted sign moves the other way. Only the posting side
// needs this; real swipes already arrive mirrored by the setting.
// Measured upstream on a MacBook Air (M4), macOS 27.0 (26A428).
func postedSwipeSign(naturalScrolling: Bool) -> Double {
    naturalScrolling ? 1 : -1
}

let postedSign: Double = {
    guard needsAugmentation else { return 1 } // pre-27 path untested with it off
    let natural = CFPreferencesCopyAppValue(
        "com.apple.swipescrolldirection" as CFString, kCFPreferencesAnyApplication) as? Bool ?? true
    return postedSwipeSign(naturalScrolling: natural)
}()

// MARK: - macOS 26 path: bare Dock swipe, near-zero progress

// Correct on 26.6+. On 26.0-26.5 the window server drops the destination's
// surfaces on a zero-travel switch (blank landing); there is no fix from outside.
func postDockSwipe(_ phase: GesturePhase, right: Bool) {
    guard let ev = CGEvent(source: nil) else { return }
    // Near-zero progress commits with nothing left to animate. Not FLT_TRUE_MIN:
    // that subnormal flushes to zero on Apple Silicon and loses the sign.
    let progress = 1e-4 * (right ? 1 : -1)
    let velocity = gestureVelocity * (right ? 1 : -1)
    ev.setIntegerValueField(fieldCGSEventType, value: kCGSEventDockControl)
    ev.setIntegerValueField(fieldGestureHIDType, value: kIOHIDEventTypeDockSwipe)
    ev.setIntegerValueField(fieldGesturePhase, value: phase.rawValue)
    ev.setDoubleValueField(fieldSwipeProgress, value: progress)
    ev.setIntegerValueField(fieldSwipeMotion, value: kCGGestureMotionHorizontal)
    ev.setDoubleValueField(fieldSwipeVelocityX, value: velocity)
    ev.setDoubleValueField(fieldSwipeVelocityY, value: velocity)
    ev.setIntegerValueField(.eventSourceUserData, value: spacehopEventTag)
    ev.post(tap: .cgSessionEventTap)
}

// MARK: - macOS 27 path: IOHID payload + companion events

// 16.16 fixed point. A tiny nonzero value keeps its sign instead of becoming 0.
func fixed1616(_ v: Double) -> Int32 {
    let f = Int32(truncatingIfNeeded: Int64(v * 65536.0))
    if f == 0 && v != 0 { return v > 0 ? 1 : -1 }
    return f
}

// Little-endian byte buffer helpers for the packed IOHID structs.
extension Array where Element == UInt8 {
    mutating func le(_ v: UInt16) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func le(_ v: UInt32) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func le(_ v: UInt64) { Swift.withUnsafeBytes(of: v.littleEndian) { append(contentsOf: $0) } }
    mutating func le(_ v: Int32)  { le(UInt32(bitPattern: v)) }
}

// The serialized IOHID queue payload macOS 27 checks a synthetic swipe against:
// a queue header, a fluid-touch gesture record, and (on motion or end) a
// velocity record. Built only from the event's own fields.
func generateIOHIDPayload(_ ev: CGEvent) -> [UInt8] {
    let phase    = ev.getIntegerValueField(fieldGesturePhase)
    let motion   = ev.getIntegerValueField(fieldSwipeMotion)
    let progress = ev.getDoubleValueField(fieldSwipeProgress)
    let posX     = ev.getDoubleValueField(fieldSwipePositionX)
    let posY     = ev.getDoubleValueField(fieldSwipePositionY)
    let velX     = ev.getDoubleValueField(fieldSwipeVelocityX)
    let velY     = ev.getDoubleValueField(fieldSwipeVelocityY)
    let mask     = ev.getIntegerValueField(fieldSwipeMask)
    // macOS 27 requires the velocity record on the terminal phase (dropping it
    // stops the switch), even when velocities are zero on other phases.
    let includeVelocity = velX != 0 || velY != 0 || phase == GesturePhase.ended.rawValue

    var p = [UInt8]()
    // IOHIDSystemQueueElementHeader (28 bytes)
    let ts = ev.timestamp
    p.le(ts != 0 ? ts : mach_absolute_time())   // timestamp
    p.le(UInt64(0))                             // sender_id
    p.le(UInt32(0))                             // options
    p.le(UInt32(0))                             // attribute_length
    p.le(UInt32(includeVelocity ? 2 : 1))       // event_count
    // IOHIDFluidTouchGestureData (40 bytes): 16-byte base + fields
    p.le(UInt32(40))                            // base.size
    p.le(UInt32(23))                            // base.type = fluid-touch gesture
    p.le(UInt32((UInt32(truncatingIfNeeded: phase) & 0xFF) << 24)) // base.options
    p.append(0); p.append(0); p.append(0); p.append(0)            // base.depth + reserved[3]
    p.le(fixed1616(posX))                       // position_x
    p.le(fixed1616(posY))                       // position_y
    p.le(Int32(0))                              // position_z
    p.le(UInt32(truncatingIfNeeded: mask))      // swipe_mask
    p.le(UInt16(truncatingIfNeeded: motion))    // gesture_motion
    p.le(UInt16(3))                             // gesture_flavor = Dock primary
    p.le(fixed1616(progress))                   // swipe_progress
    if includeVelocity {
        // IOHIDVelocityEventData (28 bytes): 16-byte base + 3 fixed velocities
        p.le(UInt32(28))                        // base.size
        p.le(UInt32(9))                         // base.type = velocity
        p.le(UInt32(0))                         // base.options
        p.append(1); p.append(0); p.append(0); p.append(0)       // base.depth = 1 + reserved
        p.le(fixed1616(velX))                   // velocity_x
        p.le(fixed1616(velY))                   // velocity_y
        p.le(Int32(0))                          // velocity_z
    }
    return p
}

// Round-trips the event through its serialized form to append the payload under
// field 4205, which the normal setters cannot write.
func augment(_ ev: CGEvent) -> CGEvent? {
    guard let cf = ev.data else { return nil }
    var bytes = [UInt8](cf as Data)
    // Serialized-event format must be version 2 (header 00 00 00 02).
    guard bytes.count >= 4, bytes[0] == 0, bytes[1] == 0, bytes[2] == 0, bytes[3] == 2 else { return nil }
    let payload = generateIOHIDPayload(ev)
    let len = payload.count
    bytes.append(UInt8((len >> 8) & 0xFF))
    bytes.append(UInt8(len & 0xFF))
    bytes.append(UInt8((kRawIOHIDPayloadTag >> 8) & 0xFF))
    bytes.append(UInt8(kRawIOHIDPayloadTag & 0xFF))
    bytes.append(contentsOf: payload)
    return CGEvent(withDataAllocator: nil, data: Data(bytes) as CFData)
}

func makeAugmentedDockEvent(_ phase: GesturePhase, right: Bool) -> CGEvent? {
    guard let ev = CGEvent(source: nil) else { return nil }
    ev.setIntegerValueField(fieldCGSEventType, value: kCGSEventDockControl)
    ev.setIntegerValueField(fieldGestureHIDType, value: kIOHIDEventTypeDockSwipe)
    ev.setIntegerValueField(fieldGesturePhase, value: phase.rawValue)
    // Small but not near-zero progress. The ±9999 fling on .ended is what commits
    // the switch in one frame; this value decides whether the destination is
    // drawn. Upstream measured on macOS 27.0.1: 1e-4 landed on a black screen in
    // up to 13 of 20 switches; 0.03 and above landed 0 of 40 black, still in one
    // frame. 0.1 leaves margin. Raise it if black landings come back; do not set
    // it to 0 (fixed1616 would write 0 into the payload).
    // On the 27 path direction is inverted: rightward = negative progress.
    ev.setDoubleValueField(fieldSwipeProgress, value: (right ? -0.1 : 0.1) * postedSign)
    ev.setIntegerValueField(fieldSwipeMotion, value: kCGGestureMotionHorizontal)
    ev.setDoubleValueField(fieldSwipePositionX, value: 0.1)
    // A strong fling velocity on the terminal phase commits the switch.
    if phase == .ended {
        ev.setDoubleValueField(fieldSwipeVelocityX, value: (right ? -9999.0 : 9999.0) * postedSign)
    }
    return ev
}

// Posts a DockControl event and its paired companion gesture event.
func postPair(_ dock: CGEvent) {
    guard let companion = CGEvent(source: nil) else { return }
    companion.setIntegerValueField(.eventSourceUserData, value: spacehopEventTag)
    companion.setIntegerValueField(fieldCGSEventType, value: kCGSEventGesture)
    dock.post(tap: .cgSessionEventTap)
    companion.post(tap: .cgSessionEventTap)
}

// MARK: - Switch core (hotkey, swipe, and CLI all call only this)

// A began/changed/ended sequence must complete: a partial one leaves the Dock
// mid-gesture on a blank Space. On the 27 path all three events are built first,
// and nothing is posted if any of them fails to build.
func postSwitchGesture(right: Bool) {
    if needsAugmentation {
        var events: [CGEvent] = []
        for phase in [GesturePhase.began, .changed, .ended] {
            guard let dock = makeAugmentedDockEvent(phase, right: right),
                  let aug = augment(dock) else { return }
            // Tag after augment(): its serialize round-trip drops the user-data field.
            aug.setIntegerValueField(.eventSourceUserData, value: spacehopEventTag)
            events.append(aug)
        }
        events.forEach(postPair)
    } else {
        postDockSwipe(.began, right: right)
        postDockSwipe(.changed, right: right)
        postDockSwipe(.ended, right: right)
    }
}

// Index of the Space one step over, or nil at the first/last Space. Stopping at
// the edge avoids the rubber-band bounce (and on 27 a swipe the Dock would reject).
func nextIndex(current: Int, count: Int, right: Bool) -> Int? {
    let target = current + (right ? 1 : -1)
    return (0..<count).contains(target) ? target : nil
}

// The gesture commits asynchronously, so on rapid presses the Space list can be
// stale. Trust our own prediction for a short window after a switch. macOS 27's
// list settles slower after a synthetic switch, so the window is wider there.
var predictedIndex: Int?
var predictedDisplay: String?
var predictionTime = Date.distantPast
let predictionWindow = needsAugmentation ? 0.4 : 0.25

func switchSpace(right: Bool) {
    guard let info = spaceInfo() else {
        postSwitchGesture(right: right)
        return
    }
    var current = info.currentIndex
    // Use the prediction only on the display it was made for; the cursor may have moved.
    if let p = predictedIndex, predictedDisplay == info.display,
       Date().timeIntervalSince(predictionTime) < predictionWindow {
        current = p
    }
    guard let target = nextIndex(current: current, count: info.ids.count, right: right) else { return }
    postSwitchGesture(right: right)
    predictedIndex = target
    predictedDisplay = info.display
    predictionTime = Date()
}
