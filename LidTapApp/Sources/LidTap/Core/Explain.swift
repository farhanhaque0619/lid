import Foundation

extension TapRecord {
    /// One or two plain sentences on what happened to this tap and what to do about it. Nil when nothing needs saying.
    var tip: String? {
        let d = detail.lowercased()
        switch outcome {
        case .acted, .recorded:
            return nil
        case .practiced:
            return "Practice mode: the zone was recognised and nothing ran. Turn on actions from the menu bar when the readings look right."
        case .confirming:
            return "This zone asks for two taps. Tap it again within three seconds to run it."
        case .untrained:
            return "LidTap feels your taps but hasn't learned your zones yet. Click Calibrate in the menu bar."
        case .guarded:
            return "Only the Privacy Guard zone works while the guard is on. Tap it again, or click anywhere, to come back."
        case .ignored:
            if d.contains("typing") || d.contains("key") { return "Taps within a third of a second of a keystroke are ignored. Finish typing, pause, then tap." }
            if d.contains("click") { return "A trackpad click shakes the laptop like a tap. Lift your hand off the trackpad, then tap." }
            if d.contains("pointer") { return "The pointer was moving. Take your hand off the trackpad or mouse before you tap." }
            if d.contains("scroll") { return "Scrolling shakes the laptop. Pause, then tap." }
            if d.contains("still moving") { return "The screen was still wobbling from the last tap or a bump. Wait about half a second between taps." }
            if d.contains("lid") { return "The lid angle changed. Taps while the lid moves are ignored; hold it still and tap again." }
            return "Ignored because of typing, clicking or movement right around the tap."
        case .rejected:
            if d.contains("too soft") { return "Below the minimum tap strength. A quick, light flick is enough. If crisp taps keep being refused, lower the minimum in Settings › Detection." }
            if d.contains("not sure") { return "The recogniser wasn't confident enough to act. Tap closer to the dot you calibrated on, or add taps to this zone in Settings › Training." }
            if d.contains("unfamiliar") { return "Unlike anything recorded, for example a different lid angle or surface. Calibrate Again adds examples; Settings › Training can relax \"Ignore unfamiliar taps\"." }
            if d.contains("bump") { return "It matched your recorded bumps rather than a tap, so nothing ran." }
            return "The tap was rejected rather than guessed, so nothing ran."
        }
    }
}
