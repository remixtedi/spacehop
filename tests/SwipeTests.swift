import CoreGraphics

func u32(_ b: [UInt8], at i: Int) -> UInt32 {
    UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
}

func test_fixed1616() {
    check(fixed1616(1.0) == 65536, "1.0 -> 65536")
    check(fixed1616(0.1) == 6553, "0.1 -> 6553")
    check(fixed1616(1e-9) == 1, "tiny positive keeps its sign")
    check(fixed1616(-1e-9) == -1, "tiny negative keeps its sign")
    check(fixed1616(0) == 0, "0 -> 0")
}

func test_payload_layout() {
    // Ended phase with a fling: header + gesture record + velocity record.
    let ended = makeAugmentedDockEvent(.ended, right: true)!
    let p = generateIOHIDPayload(ended)
    check(p.count == 96, "ended payload is 28 + 40 + 28 bytes, got \(p.count)")
    check(u32(p, at: 24) == 2, "event_count 2")
    check(u32(p, at: 28) == 40, "gesture record size 40")
    check(u32(p, at: 32) == 23, "gesture record type 23 (fluid touch)")
    check(p[39] == UInt8(GesturePhase.ended.rawValue), "phase in top byte of options")
    check(u32(p, at: 68) == 28, "velocity record size 28")
    check(u32(p, at: 72) == 9, "velocity record type 9")

    // Began phase, no velocity: no velocity record.
    let began = makeAugmentedDockEvent(.began, right: true)!
    let q = generateIOHIDPayload(began)
    check(q.count == 68, "began payload is 28 + 40 bytes, got \(q.count)")
    check(u32(q, at: 24) == 1, "event_count 1")
}

func test_augment_header() {
    let dock = makeAugmentedDockEvent(.began, right: true)!
    check(augment(dock) != nil, "augment produces an event")
}

func test_postedSign_naturalOff() {
    check(postedSwipeSign(naturalScrolling: true) == 1, "natural scrolling on -> +1")
    check(postedSwipeSign(naturalScrolling: false) == -1, "natural scrolling off -> -1")
}

func test_clamp_and_prediction() {
    check(nextIndex(current: 4, count: 6, right: true) == 5, "second-to-last -> last")
    check(nextIndex(current: 5, count: 6, right: true) == nil, "last + right -> nothing")
    check(nextIndex(current: 0, count: 6, right: false) == nil, "first + left -> nothing")
    check(nextIndex(current: 3, count: 6, right: false) == 2, "middle + left -> previous")
}
