import AppKit
import SwiftUI

enum ActionKind: String, Codable, CaseIterable, Identifiable {
    case none
    case desktopLeft, desktopRight, missionControl
    case playPause, nextTrack, previousTrack, volumeUp, volumeDown, volumeMute
    case newNote, openApp, openLink
    case shortcut, runShortcut
    case muteMic, lockScreen
    case privacyGuard
    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "Nothing"
        case .desktopLeft: "Desktop Left"
        case .desktopRight: "Desktop Right"
        case .missionControl: "Mission Control"
        case .playPause: "Play / Pause"
        case .nextTrack: "Next Track"
        case .previousTrack: "Previous Track"
        case .volumeUp: "Volume Up"
        case .volumeDown: "Volume Down"
        case .volumeMute: "Mute Sound"
        case .newNote: "New Note"
        case .openApp: "Open App"
        case .openLink: "Open Link"
        case .shortcut: "Keyboard Shortcut"
        case .runShortcut: "Run Apple Shortcut"
        case .muteMic: "Mute Microphone"
        case .lockScreen: "Lock Screen"
        case .privacyGuard: "Privacy Guard"
        }
    }

    /// One plain sentence on what the action does, shown under the picker and in the menu.
    var detail: String {
        switch self {
        case .none: "This zone does nothing"
        case .desktopLeft: "Switch to the Space on the left, like pressing ⌃←"
        case .desktopRight: "Switch to the Space on the right, like pressing ⌃→"
        case .missionControl: "Show every open window and desktop"
        case .playPause: "Play or pause whatever is playing: Music, Spotify, a browser tab"
        case .nextTrack: "Skip to the next track"
        case .previousTrack: "Go back a track"
        case .volumeUp: "Turn the volume up one step"
        case .volumeDown: "Turn the volume down one step"
        case .volumeMute: "Mute or unmute the speakers"
        case .newNote: "Open Notes with a fresh note"
        case .openApp: "Launch an app, or bring it to the front if it is already open"
        case .openLink: "Open a web address, or a link like shortcuts:// or raycast://, in its app"
        case .shortcut: "Press a key combination of your choice, exactly as if you typed it"
        case .runShortcut: "Run one of your Apple Shortcuts by name, with no window"
        case .muteMic: "Mute every microphone, or unmute them if they are muted"
        case .lockScreen: "Lock the Mac right away, like pressing ⌃⌘Q"
        case .privacyGuard: "Mute every mic, turn the meeting camera off and hide every screen"
        }
    }

    var symbol: String {
        switch self {
        case .none: "minus"
        case .desktopLeft: "rectangle.lefthalf.inset.filled.arrow.left"
        case .desktopRight: "rectangle.righthalf.inset.filled.arrow.right"
        case .missionControl: "rectangle.3.group"
        case .playPause: "playpause.fill"
        case .nextTrack: "forward.end.fill"
        case .previousTrack: "backward.end.fill"
        case .volumeUp: "speaker.wave.3.fill"
        case .volumeDown: "speaker.wave.1.fill"
        case .volumeMute: "speaker.slash.fill"
        case .newNote: "square.and.pencil"
        case .openApp: "arrow.up.forward.app"
        case .openLink: "link"
        case .shortcut: "keyboard"
        case .runShortcut: "wand.and.stars"
        case .muteMic: "mic.slash.fill"
        case .lockScreen: "lock.fill"
        case .privacyGuard: "eye.slash"
        }
    }

    /// Each action wears the hue of the Mac feature it belongs to.
    var tint: Color {
        switch self {
        case .none: Color(nsColor: .tertiaryLabelColor)
        case .desktopLeft, .desktopRight, .missionControl: .blue
        case .playPause, .nextTrack, .previousTrack, .volumeUp, .volumeDown, .volumeMute: .pink
        case .newNote: .yellow
        case .openApp: .teal
        case .openLink: .cyan
        case .shortcut: .orange
        case .runShortcut: .purple
        case .muteMic: .mint
        case .lockScreen: .red
        case .privacyGuard: .indigo
        }
    }

    /// Group used to organise the action picker.
    var group: String {
        switch self {
        case .none: "Nothing"
        case .desktopLeft, .desktopRight, .missionControl: "Desktop"
        case .playPause, .nextTrack, .previousTrack, .volumeUp, .volumeDown, .volumeMute: "Media"
        case .newNote, .openApp, .openLink: "Apps"
        case .shortcut, .runShortcut: "Custom"
        case .muteMic, .lockScreen: "System"
        case .privacyGuard: "Privacy"
        }
    }

    static let groupOrder = ["Nothing", "Desktop", "Media", "Apps", "Custom", "System", "Privacy"]

    /// Whether the action synthesises key events (needs Accessibility permission).
    var needsAccessibility: Bool {
        switch self {
        case .desktopLeft, .desktopRight, .newNote, .playPause, .nextTrack, .previousTrack,
             .volumeUp, .volumeDown, .volumeMute, .shortcut, .lockScreen: true
        // Privacy Guard's blur and mic mute work without it; only the camera shortcut needs it (reported in the overlay).
        // Mission Control opens as an app and only falls back to a keystroke.
        case .none, .openApp, .openLink, .runShortcut, .muteMic, .missionControl, .privacyGuard: false
        }
    }

    /// Whether the action needs something chosen in Settings before it can run.
    var needsSetup: Bool {
        switch self {
        case .openApp, .openLink, .shortcut, .runShortcut: true
        default: false
        }
    }
}

/// A named group of actions for the picker.
struct ActionGroup: Identifiable {
    let name: String
    let kinds: [ActionKind]
    var id: String { name }

    static let all: [ActionGroup] = ActionKind.groupOrder.compactMap { name in
        let kinds = ActionKind.allCases.filter { $0.group == name }
        return kinds.isEmpty ? nil : ActionGroup(name: name, kinds: kinds)
    }
}

struct ZoneAction: Codable, Equatable, Hashable {
    var kind: ActionKind = .none
    var appBundleID: String?
    var appName: String?
    /// For `.shortcut`: the keys to press.
    var keyCombo: KeyCombo?
    /// For `.runShortcut`: the Shortcut's name. For `.openLink`: the address.
    var text: String?
    /// Ask for a second tap within a few seconds before running (for anything you'd rather not trigger by accident).
    var confirmTwice = false

    init(kind: ActionKind = .none, appBundleID: String? = nil, appName: String? = nil,
         keyCombo: KeyCombo? = nil, text: String? = nil, confirmTwice: Bool = false) {
        self.kind = kind
        self.appBundleID = appBundleID
        self.appName = appName
        self.keyCombo = keyCombo
        self.text = text
        self.confirmTwice = confirmTwice
    }

    enum CodingKeys: String, CodingKey { case kind, appBundleID, appName, keyCombo, text, confirmTwice }

    /// Tolerant of files from older or newer versions: missing keys take defaults, an unknown action kind becomes Nothing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = (try c.decodeIfPresent(String.self, forKey: .kind)).flatMap(ActionKind.init(rawValue:)) ?? ActionKind.none
        appBundleID = try c.decodeIfPresent(String.self, forKey: .appBundleID)
        appName = try c.decodeIfPresent(String.self, forKey: .appName)
        keyCombo = try c.decodeIfPresent(KeyCombo.self, forKey: .keyCombo)
        text = try c.decodeIfPresent(String.self, forKey: .text)
        confirmTwice = try c.decodeIfPresent(Bool.self, forKey: .confirmTwice) ?? false
    }

    var title: String {
        switch kind {
        case .openApp: return appName ?? kind.title
        case .shortcut: return keyCombo?.label ?? kind.title
        case .runShortcut:
            let name = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? kind.title : "Shortcut: \(name)"
        case .openLink:
            guard let url = Self.validLink(text) else { return kind.title }
            return "Open \(url.host ?? url.scheme ?? "link")"
        default: return kind.title
        }
    }

    /// A usable link from what was typed: bare domains get https://, file and script links are refused.
    static func validLink(_ raw: String?) -> URL? {
        var s = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty, !s.contains(" ") else { return nil }
        if !s.contains("://"), !s.contains(":"), s.contains(".") { s = "https://" + s }
        guard let url = URL(string: s), let scheme = url.scheme?.lowercased(), !scheme.isEmpty,
              scheme != "file", scheme != "javascript", scheme != "data" else { return nil }
        if scheme == "http" || scheme == "https" { guard let host = url.host, !host.isEmpty else { return nil } }
        return url
    }

    /// False while the action still needs something chosen in Settings.
    var isConfigured: Bool { setupHint == nil }

    /// What is missing, for the UI and the action runner.
    var setupHint: String? {
        switch kind {
        case .openApp where appBundleID == nil: "Choose an app for this zone in Settings."
        case .shortcut where keyCombo == nil: "Record a key combination for this zone in Settings."
        case .runShortcut where (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty: "Type the Shortcut's name for this zone in Settings."
        case .openLink where Self.validLink(text) == nil: "Enter a full link (https://…) for this zone in Settings."
        default: nil
        }
    }

    static func defaults(for grid: Grid) -> [String: ZoneAction] {
        let layout: [ActionKind]
        switch (grid.rows, grid.cols) {
        case (2, 2): layout = [.desktopLeft, .desktopRight, .playPause, .privacyGuard]
        case (2, 3): layout = [.desktopLeft, .newNote, .desktopRight, .previousTrack, .playPause, .privacyGuard]
        case (3, 3): layout = [.desktopLeft, .newNote, .desktopRight, .previousTrack, .playPause, .nextTrack, .openApp, .none, .privacyGuard]
        default: layout = []
        }
        var out: [String: ZoneAction] = [:]
        for i in 0..<grid.count { out[zoneLabel(i)] = ZoneAction(kind: i < layout.count ? layout[i] : .none) }
        return out
    }
}
