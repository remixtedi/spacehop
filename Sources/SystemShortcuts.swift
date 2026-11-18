import Foundation

// Turns the system's own animated "Move left/right a space" shortcuts
// (Ctrl+Left/Right, symbolic hotkeys 79 and 81) off or back on. While they are on
// they take Ctrl+arrow before spacehop sees it. Ported from noswoosh (see
// AUDIT.md, "System shortcuts") without the `defaults` and `killall` calls.

@_silgen_name("SLSSetSymbolicHotKeyEnabled")
func SLSSetSymbolicHotKeyEnabled(_ hotKey: Int32, _ enabled: Bool) -> Int32

// hotkey id -> (key code, Ctrl modifier mask) of the macOS default binding
private let ctrlArrowHotKeys: [(id: Int32, keyCode: Int)] = [(79, 123), (81, 124)]
private let ctrlModifierMask = 8650752
private let domain = "com.apple.symbolichotkeys" as CFString
private let key = "AppleSymbolicHotKeys" as CFString

func setCtrlArrowShortcuts(enabled: Bool) {
    // Live state for the running login session.
    for hotKey in ctrlArrowHotKeys {
        _ = SLSSetSymbolicHotKeyEnabled(hotKey.id, enabled)
    }

    // Saved state for future logins. Only entries 79 and 81 are touched; a
    // binding the user changed is kept, a missing one gets the macOS default.
    var all = CFPreferencesCopyValue(key, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        as? [String: Any] ?? [:]
    for hotKey in ctrlArrowHotKeys {
        var entry = all[String(hotKey.id)] as? [String: Any] ?? [:]
        entry["enabled"] = enabled
        if entry["value"] == nil {
            entry["value"] = ["parameters": [65535, hotKey.keyCode, ctrlModifierMask], "type": "standard"]
        }
        all[String(hotKey.id)] = entry
    }
    CFPreferencesSetValue(key, all as CFDictionary, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
    CFPreferencesSynchronize(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
}
