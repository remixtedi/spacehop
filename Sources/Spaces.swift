import Cocoa

// Reads which Spaces exist and which one is showing. Read-only: nothing here
// changes any state. Ported from noswoosh (see AUDIT.md, "Space lookup").

// MARK: - Private SkyLight reads

typealias CGSConnectionID = UInt32

@_silgen_name("SLSMainConnectionID")
func SLSMainConnectionID() -> CGSConnectionID

@_silgen_name("SLSCopyManagedDisplaySpaces")
func SLSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> Unmanaged<CFArray>

@_silgen_name("SLSGetActiveSpace")
func SLSGetActiveSpace(_ cid: CGSConnectionID) -> UInt64

// Returns the union of spaces the given windows live on (mask 0x7 = all).
@_silgen_name("SLSCopySpacesForWindows")
func SLSCopySpacesForWindows(_ cid: CGSConnectionID, _ mask: Int32,
                             _ windows: CFArray) -> Unmanaged<CFArray>

let cid = SLSMainConnectionID()

func activeSpaceID() -> UInt64 { SLSGetActiveSpace(cid) }

struct SpaceInfo {
    let ids: [UInt64]
    let currentIndex: Int
    // "Display Identifier" of the display this list belongs to, so a prediction
    // made on one display is never applied to another's list.
    let display: String?
}

// UUID string of the display under the mouse cursor, in the same form as the
// "Display Identifier" values in SLSCopyManagedDisplaySpaces.
func cursorDisplayUUID() -> String? {
    guard let location = CGEvent(source: nil)?.location else { return nil }
    var displayID = CGDirectDisplayID()
    var matched: UInt32 = 0
    guard CGGetDisplaysWithPoint(location, 1, &displayID, &matched) == .success,
          matched > 0,
          let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue()
    else { return nil }
    return CFUUIDCreateString(nil, uuid) as String
}

// Space list for the display the switch will land on, plus that display's
// current index in it. The list includes fullscreen spaces, which the swipe
// traverses too.
//
// The Dock routes a Dock-swipe to the display under the mouse cursor, not the one
// holding keyboard focus. SLSGetActiveSpace tracks keyboard focus, so on more than
// one display we ask the cursor's display for its own current space instead.
func spaceInfo() -> SpaceInfo? {
    guard let displays = SLSCopyManagedDisplaySpaces(cid).takeRetainedValue() as? [[String: Any]] else {
        return nil
    }

    func info(_ display: [String: Any], current: UInt64) -> SpaceInfo? {
        guard let spaces = display["Spaces"] as? [[String: Any]] else { return nil }
        let ids = spaces.compactMap { ($0["id64"] as? NSNumber)?.uint64Value }
        guard let idx = ids.firstIndex(of: current) else { return nil }
        return SpaceInfo(ids: ids, currentIndex: idx,
                         display: display["Display Identifier"] as? String)
    }

    if displays.count > 1, let uuid = cursorDisplayUUID(),
       let display = displays.first(where: { ($0["Display Identifier"] as? String) == uuid }),
       let current = (display["Current Space"] as? [String: Any])?["id64"] as? NSNumber,
       let result = info(display, current: current.uint64Value) {
        return result
    }

    // One managed display (a single screen, or "Displays have separate Spaces"
    // off), or the cursor lookup failed.
    let active = SLSGetActiveSpace(cid)
    for display in displays {
        if let result = info(display, current: active) { return result }
    }
    return nil
}

// Is any ordinary (layer 0) window on this space?
func spaceHasWindows(_ spaceID: UInt64) -> Bool {
    let list = CGWindowListCopyWindowInfo([.excludeDesktopElements],
                                          kCGNullWindowID) as? [[String: Any]] ?? []
    let ids = list.compactMap { w -> UInt32? in
        guard (w[kCGWindowLayer as String] as? Int) == 0 else { return nil }
        return w[kCGWindowNumber as String] as? UInt32
    }
    guard !ids.isEmpty else { return false }
    let spaces = SLSCopySpacesForWindows(cid, 0x7, ids as CFArray)
        .takeRetainedValue() as? [NSNumber] ?? []
    return spaces.contains { $0.uint64Value == spaceID }
}

// MARK: - macOS version

// Major version of the running OS (not the build SDK), or 0 if it can't be read.
func macOSMajorVersion() -> Int {
    var buf = [CChar](repeating: 0, count: 32)
    var size = buf.count
    guard sysctlbyname("kern.osproductversion", &buf, &size, nil, 0) == 0,
          let major = Int(String(cString: buf).split(separator: ".").first ?? "") else {
        return 0
    }
    return major
}
let macOSMajor = macOSMajorVersion()

// macOS 27+ only accepts a synthetic Dock swipe that carries a serialized IOHID
// payload. Decided by OS version alone; there is no override.
let needsAugmentation = macOSMajor >= 27
