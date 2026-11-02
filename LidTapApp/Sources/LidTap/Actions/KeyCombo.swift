import AppKit
import CoreGraphics

/// A key combination for the Keyboard Shortcut action: the virtual key code, the modifier flags to post it with,
/// and a label such as "⇧⌘3" built when it was recorded (so it reflects the keyboard layout in use then).
struct KeyCombo: Codable, Equatable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt64
    var label: String

    var flags: CGEventFlags { CGEventFlags(rawValue: modifiers) }

    /// The combo behind a key-down event seen by the shortcut recorder, or nil for a key with no name.
    static func from(_ event: NSEvent) -> KeyCombo? {
        let mods = event.modifierFlags.intersection([.command, .option, .control, .shift, .function])
        var flags: CGEventFlags = []
        if mods.contains(.command) { flags.insert(.maskCommand) }
        if mods.contains(.option) { flags.insert(.maskAlternate) }
        if mods.contains(.control) { flags.insert(.maskControl) }
        if mods.contains(.shift) { flags.insert(.maskShift) }
        if mods.contains(.function) { flags.insert(.maskSecondaryFn) }
        let label = label(keyCode: event.keyCode, flags: flags, characters: event.charactersIgnoringModifiers)
        guard !label.isEmpty else { return nil }
        return KeyCombo(keyCode: event.keyCode, modifiers: flags.rawValue, label: label)
    }

    /// "⌃⌥⇧⌘" in Apple's order, then the key's name. "fn" is shown only for keys that don't imply it.
    static func label(keyCode: UInt16, flags: CGEventFlags, characters: String?) -> String {
        let name = KeyNames.name(for: keyCode, characters: characters)
        var parts: [String] = []
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }
        if flags.contains(.maskSecondaryFn) && KeyNames.special[keyCode] == nil { parts.append("fn ") }
        return parts.joined() + name
    }

    /// True for a combination worth recording: at least one real modifier, or a function key on its own.
    var isUsable: Bool {
        !flags.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]).isEmpty
            || (KeyNames.special[keyCode]?.hasPrefix("F") ?? false)
    }
}

/// Names for keys that have no printable character.
enum KeyNames {
    static let special: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟", 123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9",
        109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
        79: "F18", 80: "F19", 90: "F20",
    ]

    static func name(for keyCode: UInt16, characters: String?) -> String {
        if let s = special[keyCode] { return s }
        if let c = characters, let scalar = c.unicodeScalars.first, scalar.value >= 0x20, scalar.value != 0x7F, scalar.value < 0xF700 {
            return c.uppercased()
        }
        return "Key \(keyCode)"
    }
}
