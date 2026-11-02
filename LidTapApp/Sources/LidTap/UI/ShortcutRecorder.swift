import AppKit
import SwiftUI

/// Records a key combination: click Record, press the keys, done. Esc cancels. Uses a local event monitor, so it only
/// sees keys while the Settings window is in front and needs no permission.
struct ShortcutRecorder: View {
    @Binding var combo: KeyCombo?
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 8) {
            Text(recording ? "Press the keys…" : (combo?.label ?? "None"))
                .font(.body.monospaced())
                .foregroundStyle(recording || combo != nil ? Color.primary : Color.secondary)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .frame(minWidth: 130)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(recording ? Color.accentColor.opacity(0.15) : Color(nsColor: .controlBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(recording ? Color.accentColor : Color.secondary.opacity(0.3)))
            Button(recording ? "Cancel" : (combo == nil ? "Record…" : "Change…")) {
                if recording { stop() } else { start() }
            }
            if combo != nil && !recording {
                Button("Clear") { combo = nil }
            }
        }
        .onDisappear { stop() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keyboard shortcut: \(combo?.label ?? "none")")
    }

    private func start() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { stop(); return nil }  // Esc cancels
            if let c = KeyCombo.from(event), c.isUsable {
                combo = c
                stop()
            }
            return nil  // never let the keys reach the window while recording
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = false
    }
}
