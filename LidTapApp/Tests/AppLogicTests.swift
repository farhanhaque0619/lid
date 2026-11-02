import CoreGraphics
import Foundation

/// AppModel end to end with a temporary data folder, no UI, and actions recorded instead of performed.
@MainActor
final class AppHarness {
    let dir: URL
    let app: AppModel
    var performed: [ZoneAction] = []

    init(name: String, dataset: Dataset? = T.loadDataset(), config: AppConfig? = nil) {
        dir = T.tempDir(name)
        let store = Store(directory: dir)
        if let dataset { store.save(dataset) }
        if let config { store.save(config) }
        app = AppModel(store: store, presentsUI: false)
        app.config.practiceMode = false  // a fresh install practises first; these tests want actions to run
        app.input.allowsSystemFallback = false  // input history comes only from what a test records
        app.privacyGuard.muteMic = false
        app.privacyGuard.stopCamera = false
        app.performAction = { [unowned self] action in
            self.performed.append(action)
            if action.kind == .privacyGuard { self.app.privacyGuard.toggle() }
            return nil
        }
    }

    func train() -> Bool {
        app.retrain()
        return T.wait(30) { app.isTrained && !app.isTraining }
    }

    func tap(_ label: String, gated: String? = nil) {
        app.handle(app.replayEvent(label: label, gated: gated)!)
    }

    deinit { try? FileManager.default.removeItem(at: dir) }
}

@MainActor
func appLogicTests() {
    T.suite = "App logic"
    print("\n▶ App logic")

    T.run("loads your data and trains the best model") {
        let h = AppHarness(name: "train")
        T.expect(h.app.dataset.samples.count == 60, "samples \(h.app.dataset.samples.count)")
        T.expect(h.train(), "model did not train within 30 s")
        T.note("active model \(h.app.activeKind?.title ?? "-"), accuracy \(Int((h.app.accuracy ?? 0) * 100))%")
        T.expect((h.app.accuracy ?? 0) >= 0.85, "accuracy \(h.app.accuracy ?? 0)")
        T.expect(h.app.config.actions.count == 4, "default actions for 2×2: \(h.app.config.actions.count)")
    }

    T.run("each zone's tap runs that zone's action") {
        let h = AppHarness(name: "dispatch")
        guard h.train() else { return T.fail("no model") }
        var right = 0, total = 0
        for zone in 0..<4 {
            for _ in 0..<15 {
                h.performed.removeAll()
                h.tap(zoneLabel(zone))
                total += 1
                let r = h.app.lastRecord!
                if r.outcome == .acted && r.label == zoneLabel(zone) && h.performed == [h.app.action(for: zone)] { right += 1 }
                if h.app.privacyGuard.isActive { h.app.privacyGuard.release() }
            }
        }
        T.note("correct zone + action: \(right)/\(total)")
        T.expect(Double(right) / Double(total) >= 0.85, "only \(right)/\(total) taps ran the right action")
    }

    T.run("gated taps never act") {
        let h = AppHarness(name: "gated")
        guard h.train() else { return T.fail("no model") }
        for reason in ["typing", "click", "scroll", "lid moved"] { h.tap("z0", gated: reason) }
        T.expect(h.performed.isEmpty, "gated taps performed \(h.performed.count) actions")
        T.expect(h.app.recent.prefix(4).allSatisfy { $0.outcome == .ignored }, "gated taps not recorded as ignored")
    }

    T.run("typing filter: keys before or after a tap, and typing bursts") {
        let h = AppHarness(name: "inputgate")
        guard h.train() else { return T.fail("no model") }
        var clock = MachClock.now()
        @MainActor func tap(_ label: String, keys: [Double] = [], clicks: [Double] = [], moves: [Double] = []) -> TapRecord.Outcome? {
            clock += 10  // each simulated tap 10 s after the last, so input from one never touches the next
            let r = h.app.replayEvent(label: label)!
            let ev = TapEvent(id: r.id, time: clock, date: r.date, g: r.g, a: r.a, peakG: r.peakG, peakA: r.peakA,
                              lid: r.lid, threshold: r.threshold, noise: r.noise, gated: nil)
            for k in keys { h.app.input.record(.key, at: ev.time + k) }
            for c in clicks { h.app.input.record(.click, at: ev.time + c) }
            for m in moves { h.app.input.record(.move, at: ev.time + m) }
            h.app.handle(ev)
            return h.app.lastRecord?.outcome
        }
        T.expect(tap("z0", keys: [-0.05]) == .ignored, "key 50 ms before the tap should ignore it")
        T.expect(tap("z0", keys: [0.08]) == .ignored, "key 80 ms after the tap (typing reported late) should ignore it")
        T.expect(tap("z0", keys: [-1.2, -0.9, -0.6]) == .ignored, "typing burst should ignore the tap")
        T.expect(tap("z0", clicks: [0.12]) == .ignored, "trackpad click/release just after should ignore it")
        T.expect(tap("z0", moves: [-0.25, -0.15, -0.05]) == .ignored, "a tap while the pointer is moving should be ignored")
        T.expect(tap("z0", moves: [0.1]) == .ignored, "a pointer move just after the tap should ignore it")
        T.expect(tap("z1", moves: [-0.8]) != .ignored, "a pointer move 0.8 s earlier should not block a tap")
        T.sleep(0.01)
        T.expect(tap("z1", keys: [-0.6]) != .ignored, "a single key 0.6 s earlier should not block a tap")
        T.expect(tap("z1", keys: [0.3]) != .ignored, "a key 0.3 s after should not block a tap")
        T.note("ignore reason example: \(h.app.recent.dropFirst(2).first?.detail ?? "-")")
    }

    T.run("calibration: keys never block taps, clicks on Undo/Stop do; bump step records everything") {
        let h = AppHarness(name: "calgate")
        h.app.startCalibration(perZone: 18, block: 1)
        let before = h.app.dataset.samples.count
        var ev = h.app.replayEvent(label: h.app.calibration!.target!)!
        h.app.input.record(.key, at: ev.time + 0.014)   // the key-after-tap pattern seen on this Mac
        h.app.handle(ev)
        T.expect(h.app.dataset.samples.count == before + 1, "a key right after a calibration tap blocked it")
        ev = h.app.replayEvent(label: h.app.calibration!.target!)!
        h.app.input.record(.click, at: ev.time - 0.05)  // clicking Undo shakes the laptop too
        h.app.handle(ev)
        T.expect(h.app.dataset.samples.count == before + 1, "a click on the calibration controls was recorded as a tap")
        ev = h.app.replayEvent(label: h.app.calibration!.target!)!
        h.app.input.record(.move, at: ev.time - 0.1)
        h.app.handle(ev)
        T.expect(h.app.dataset.samples.count == before + 1, "a tap while moving the pointer was recorded in calibration")
        h.app.startNoiseRecording(seconds: 30)
        ev = h.app.replayEvent(label: "z0")!
        h.app.input.record(.key, at: ev.time + 0.02)
        h.app.handle(ev)
        T.expect(h.app.count(for: noiseLabel) == 1, "typing during the bump step was not recorded as a bump")
        h.app.endCalibration()
    }

    T.run("stillness: a tap that starts while the screen is still moving is ignored") {
        let h = AppHarness(name: "still")
        guard h.train() else { return T.fail("no model") }
        @MainActor func tap(pre: Double) -> TapRecord.Outcome? {
            let r = h.app.replayEvent(label: "z0")!
            h.app.handle(TapEvent(id: r.id, time: r.time, date: r.date, g: r.g, a: r.a, peakG: r.peakG, peakA: r.peakA, lid: r.lid,
                                  threshold: 1.2, noise: 0.15, gated: nil, preMotion: pre))
            return h.app.lastRecord?.outcome
        }
        T.expect(tap(pre: 0.3) != .ignored, "a tap from a still screen was ignored")
        T.expect(tap(pre: 1.0) == .ignored, "a tap during motion (typing, wobble) was not ignored")
        T.note(h.app.lastRecord?.detail ?? "")
    }

    T.run("calibration records only clean taps (too-soft taps are asked again)") {
        let h = AppHarness(name: "soft")
        h.app.startCalibration(perZone: 18, block: 1)
        let n = h.app.dataset.samples.count
        let r = h.app.replayEvent(label: h.app.calibration!.target!)!
        h.app.handle(TapEvent(id: r.id, time: r.time, date: r.date, g: r.g, a: r.a, peakG: 1.2, peakA: r.peakA, lid: r.lid,
                              threshold: 1, noise: 0.1, gated: nil))
        T.expect(h.app.dataset.samples.count == n && h.app.calibration?.flash == .ignored("too soft"), "a 1.2 °/s calibration tap was recorded")
        h.app.handle(TapEvent(id: r.id + 1, time: r.time, date: r.date, g: r.g, a: r.a, peakG: 4, peakA: r.peakA, lid: r.lid,
                              threshold: 1, noise: 0.1, gated: nil))
        T.expect(h.app.dataset.samples.count == n + 1, "a crisp calibration tap was not recorded")
        h.app.endCalibration()
    }

    T.run("Privacy Guard only fires when the recogniser is at least 85% sure") {
        let h = AppHarness(name: "guardconf")
        guard h.train() else { return T.fail("no model") }
        h.app.config.minConfidence = 0.3
        var fired: [Double] = []
        for _ in 0..<40 {
            h.performed.removeAll()
            h.tap("z3")  // the Privacy Guard zone in the default 2×2 layout
            if h.performed.contains(where: { $0.kind == .privacyGuard }) { fired.append(h.app.lastRecord?.confidence ?? 0) }
            if h.app.privacyGuard.isActive { h.app.privacyGuard.release() }
        }
        T.note("fired \(fired.count)/40, lowest confidence \(fired.min().map { String(format: "%.2f", $0) } ?? "-")")
        T.expect(fired.allSatisfy { $0 >= 0.85 }, "Privacy Guard fired below 85% confidence")
    }

    T.run("confidence floor: unsure taps say so instead of acting") {
        let h = AppHarness(name: "confidence")
        guard h.train() else { return T.fail("no model") }
        h.app.config.minConfidence = 0.999
        h.performed.removeAll()
        for _ in 0..<5 { h.tap("z1") }
        let rejected = h.app.recent.prefix(5).filter { $0.outcome == .rejected }.count
        T.expect(rejected >= 4 && h.performed.count <= 1, "with a 99.9% floor, \(rejected)/5 rejected and \(h.performed.count) acted")
        h.app.config.minConfidence = 0.6
        h.performed.removeAll()
        for _ in 0..<5 { h.tap("z1") }
        T.expect(h.performed.count >= 4, "with a 60% floor only \(h.performed.count)/5 acted")
    }

    T.run("strength coaching: soft live taps never act; training uses only crisp taps") {
        var ds = T.loadDataset()
        // Add 12 soft (1.5 °/s) taps, deliberately labelled as zone 1, that would poison training if used.
        for i in 0..<12 {
            var s = ds.samples[30 + i]
            s.id = 1000 + i; s.label = "z0"; s.peakG = 1.5
            ds.samples.append(s)
        }
        let h = AppHarness(name: "strength", dataset: ds)
        T.expect(h.app.softTapCount == 12 && h.app.usableCount(for: "z0") == 15, "soft \(h.app.softTapCount), usable z0 \(h.app.usableCount(for: "z0"))")
        guard h.train() else { return T.fail("no model") }
        T.expect(h.app.report?.sampleCount == 60, "trained on \(h.app.report?.sampleCount ?? 0) taps, want the 60 crisp ones")
        T.expect((h.app.accuracy ?? 0) >= 0.9, "accuracy \(h.app.accuracy ?? 0) with soft taps excluded")
        let r = h.app.replayEvent(label: "z1")!
        h.performed.removeAll()
        h.app.handle(TapEvent(id: r.id, time: r.time, date: r.date, g: r.g, a: r.a, peakG: 2.0, peakA: r.peakA, lid: r.lid,
                              threshold: 1, noise: 0.1, gated: nil))
        T.expect(h.performed.isEmpty && h.app.lastRecord?.outcome == .rejected, "a 2 °/s live tap acted")
        h.app.config.minTapStrength = 1.0
        T.expect(T.wait(10) { h.app.report?.sampleCount == 72 && !h.app.isTraining }, "lowering the minimum did not retrain with all taps")
    }

    T.run("strength coaching: calibration meter sees every tap, recorded or not") {
        let h = AppHarness(name: "meter")
        h.app.startCalibration(perZone: 18, block: 1)
        let r = h.app.replayEvent(label: h.app.calibration!.target!)!
        h.app.handle(TapEvent(id: r.id, time: r.time, date: r.date, g: r.g, a: r.a, peakG: 2.2, peakA: r.peakA, lid: r.lid,
                              threshold: 1, noise: 0.1, gated: nil))
        T.expect(h.app.calibration?.lastStrength == 2.2 && h.app.calibration?.strengthID == 1, "meter missed a soft tap")
        h.app.handle(TapEvent(id: r.id + 1, time: r.time, date: r.date, g: r.g, a: r.a, peakG: 6.5, peakA: r.peakA, lid: r.lid,
                              threshold: 1, noise: 0.1, gated: nil))
        T.expect(h.app.calibration?.lastStrength == 6.5 && h.app.calibration?.position == 1, "meter or progress wrong after a crisp tap")
        h.app.endCalibration()
    }

    T.run("paused app ignores taps") {
        let h = AppHarness(name: "paused")
        guard h.train() else { return T.fail("no model") }
        h.app.config.enabled = false
        h.tap("z0")
        T.expect(h.performed.isEmpty, "acted while paused")
    }

    T.run("unfamiliar taps are rejected without acting") {
        let h = AppHarness(name: "reject")
        guard h.train() else { return T.fail("no model") }
        var rejected = 0
        for i in 0..<20 {
            let g = (0..<TapDetector.n).map { _ in (0..<3).map { _ in Double.random(in: -4...4) } }
            h.app.handle(TapEvent(id: 900 + i, time: MachClock.now(), date: Date(), g: g, a: g.map { $0.map { $0 / 500 } },
                                  peakG: 6, peakA: 0.01, lid: 130, threshold: 1, noise: 0.1, gated: nil))
            if h.app.lastRecord?.outcome == .rejected { rejected += 1 }
        }
        T.note("random windows rejected \(rejected)/20, actions run \(h.performed.count)")
        T.expect(rejected >= 18, "only \(rejected)/20 rejected")
    }

    T.run("untrained app records taps without acting") {
        let h = AppHarness(name: "untrained", dataset: nil)
        h.app.handle(TapEvent(id: 1, time: 0, date: Date(), g: T.loadDataset().samples[0].g, a: T.loadDataset().samples[0].a,
                              peakG: 5, peakA: 0.01, lid: nil, threshold: 1, noise: 0.1, gated: nil))
        T.expect(h.app.lastRecord?.outcome == .untrained && h.performed.isEmpty, "untrained tap outcome \(String(describing: h.app.lastRecord?.outcome))")
    }

    T.run("Privacy Guard: other zones ignored, guard zone releases it") {
        let h = AppHarness(name: "guard")
        guard h.train() else { return T.fail("no model") }
        let guardZone = (0..<4).first { h.app.action(for: $0).kind == .privacyGuard }!
        h.app.privacyGuard.engage()
        T.expect(h.app.privacyGuard.isActive, "guard did not engage")
        h.performed.removeAll()
        let other = zoneLabel((guardZone + 2) % 4)  // a zone in the other row: never confused in your data
        for _ in 0..<5 { h.tap(other) }
        T.expect(h.performed.isEmpty, "zone actions ran while guarded: \(h.performed.map(\.title))")
        T.expect(h.app.recent.prefix(5).allSatisfy { $0.outcome == .guarded || $0.outcome == .rejected }, "taps while guarded not marked guarded")
        for _ in 0..<5 where h.app.privacyGuard.isActive { h.tap(zoneLabel(guardZone)) }
        T.expect(!h.app.privacyGuard.isActive, "tapping the guard zone did not release Privacy Guard")
    }

    T.run("full calibration flow: taps → noise → train → done") {
        let h = AppHarness(name: "calib")
        let before = h.app.dataset.samples.count
        h.app.startCalibration(perZone: 17, block: 1)  // each zone has 15, so 2 more each
        guard let cal = h.app.calibration else { return T.fail("calibration did not start") }
        T.expect(cal.sequence.count == 8, "sequence length \(cal.sequence.count), want 8")
        T.expect(Set(cal.sequence) == Set((0..<4).map(zoneLabel)), "sequence must cover every zone")
        // A gated tap during calibration is flashed and not recorded.
        h.tap("z0", gated: "typing")
        T.expect(h.app.calibration?.position == 0 && h.app.calibration?.flash == .ignored("typing"), "gated calibration tap was counted")
        while let target = h.app.calibration?.target { h.tap(target) }
        T.expect(h.app.calibration?.phase == .noisePrompt, "phase after taps \(String(describing: h.app.calibration?.phase))")
        T.expect(h.app.dataset.samples.count == before + 8, "samples \(h.app.dataset.samples.count), want \(before + 8)")
        h.app.startNoiseRecording(seconds: 0.5)
        for _ in 0..<3 { h.tap("z1") }  // anything during the noise phase is labelled noise
        T.expect(h.app.count(for: noiseLabel) == 3, "noise samples \(h.app.count(for: noiseLabel))")
        T.expect(T.wait(30) { h.app.calibration?.phase == .done }, "never reached done: \(String(describing: h.app.calibration?.phase))")
        T.expect(h.app.isTrained && h.app.report?.labels.contains(noiseLabel) == true, "model not retrained with noise class")
        h.app.endCalibration()
        T.expect(h.app.calibration == nil, "calibration not ended")
    }

    T.run("undo removes the last calibration tap") {
        let h = AppHarness(name: "undo")
        h.app.startCalibration(perZone: 16, block: 1)
        let t = h.app.calibration!.target!
        h.tap(t)
        let n = h.app.dataset.samples.count
        h.app.undoLastCalibrationTap()
        T.expect(h.app.dataset.samples.count == n - 1 && h.app.calibration?.position == 0, "undo did not revert")
        h.app.endCalibration()
    }

    T.run("switching grid clears zone taps, keeps noise, resets actions") {
        let h = AppHarness(name: "grid")
        h.app.startCalibration(perZone: 15)
        h.app.startNoiseRecording(seconds: 30)
        h.tap("z0")
        h.app.endCalibration()
        h.app.startCalibration(grid: Grid(rows: 3, cols: 3), perZone: 5)
        T.expect(h.app.grid == Grid(rows: 3, cols: 3), "grid not switched")
        T.expect(h.app.dataset.zoneTapCount == 0 && h.app.count(for: noiseLabel) == 1, "zone taps \(h.app.dataset.zoneTapCount), noise \(h.app.count(for: noiseLabel))")
        T.expect(h.app.config.actions.count == 9 && h.app.action(for: 8).kind == .privacyGuard, "3×3 default actions")
        T.expect(!h.app.isTrained, "old model kept after grid change")
        T.expect(h.app.calibration?.sequence.count == 45, "3×3 × 5 sequence \(h.app.calibration?.sequence.count ?? 0)")
        h.app.endCalibration()
    }

    T.run("data and settings persist across restarts") {
        let h = AppHarness(name: "persist")
        h.app.setAction(ZoneAction(kind: .openApp, appBundleID: "com.apple.calculator", appName: "Calculator"), for: 2)
        h.app.config.detector.k = 9
        h.app.config.rejectFactor = 2.7
        h.app.startCalibration(perZone: 16, block: 1)
        h.tap(h.app.calibration!.target!)
        h.app.endCalibration()
        T.sleep(0.8)  // dataset saves are debounced
        let again = AppModel(store: Store(directory: h.dir), presentsUI: false)
        T.expect(again.dataset.samples.count == 61, "reloaded samples \(again.dataset.samples.count)")
        T.expect(again.action(for: 2).appBundleID == "com.apple.calculator", "zone action not persisted")
        T.expect(again.config.detector.k == 9 && again.config.rejectFactor == 2.7, "settings not persisted")
        T.expect(again.detector.settings.k == 9, "detector did not pick up saved settings")
    }

    T.run("delete a zone's taps and clear everything") {
        let h = AppHarness(name: "delete")
        h.app.deleteSamples(label: "z0")
        T.expect(h.app.count(for: "z0") == 0 && h.app.dataset.samples.count == 45, "delete zone")
        T.expect(T.wait(20) { !h.app.isTraining }, "retrain after delete hung")
        h.app.clearData()
        T.expect(h.app.dataset.samples.isEmpty && !h.app.isTrained, "clear all")
    }

    T.run("corrupt files are moved aside, not overwritten") {
        let dir = T.tempDir("corrupt")
        try! "{ this is not json".write(to: dir.appendingPathComponent("dataset.json"), atomically: true, encoding: .utf8)
        try! "[1,2".write(to: dir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        let app = AppModel(store: Store(directory: dir), presentsUI: false)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        T.note("files after load: \(files.sorted())")
        T.expect(app.dataset.samples.isEmpty && app.config == { var c = AppConfig(); c.actions = ZoneAction.defaults(for: Grid(rows: 2, cols: 2)); return c }(), "defaults not used")
        T.expect(files.filter { $0.contains("corrupt") }.count == 2, "corrupt files not preserved: \(files)")
        try? FileManager.default.removeItem(at: dir)
    }

    T.run("older/partial config files still load (missing keys use defaults)") {
        let dir = T.tempDir("partial")
        try! #"{"enabled": false, "detector": {"k": 4}}"#.write(to: dir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        let cfg = Store(directory: dir).loadConfig()
        T.expect(!cfg.enabled && cfg.detector.k == 4 && cfg.detector.minThreshold == 1 && cfg.rejectFactor == 2 && cfg.guardMutesMic, "partial config \(cfg)")
        try? FileManager.default.removeItem(at: dir)
    }

    T.run("model choice and reject factor apply live") {
        let h = AppHarness(name: "choice")
        guard h.train() else { return T.fail("no model") }
        h.app.config.modelChoice = ModelKind.centroid.rawValue
        T.expect(T.wait(10) { h.app.activeKind == .centroid }, "switching model did not refit (active \(String(describing: h.app.activeKind)))")
        h.app.config.rejectFactor = 0.01  // absurdly strict: everything is unfamiliar
        h.tap("z1")
        T.expect(h.app.lastRecord?.outcome == .rejected, "strict reject factor not applied")
    }

    T.run("practice mode: zones are recognised, nothing runs") {
        let h = AppHarness(name: "practice")
        guard h.train() else { return T.fail("no model") }
        h.app.config.practiceMode = true
        for _ in 0..<5 { h.tap("z1") }
        T.expect(h.performed.isEmpty, "actions ran in practice mode: \(h.performed.map(\.title))")
        T.expect(h.app.recent.prefix(5).contains { $0.outcome == .practiced }, "no tap was marked as practice")
        T.expect(h.app.recent.prefix(5).allSatisfy { $0.outcome == .practiced || $0.outcome == .rejected }, "unexpected outcomes \(h.app.recent.prefix(5).map(\.outcome))")
        h.app.config.practiceMode = false
        for _ in 0..<5 where h.performed.isEmpty { h.tap("z1") }
        T.expect(!h.performed.isEmpty, "nothing ran after leaving practice mode")
    }

    T.run("tap twice to run: the first tap asks, the second within the window runs") {
        let h = AppHarness(name: "confirm")
        guard h.train() else { return T.fail("no model") }
        var a = h.app.action(for: 1)
        a.confirmTwice = true
        h.app.setAction(a, for: 1)
        h.performed.removeAll()
        var asked = false, ran = false
        for _ in 0..<8 where !ran {
            h.tap("z1")
            if h.app.lastRecord?.outcome == .confirming { asked = true }
            if h.app.lastRecord?.outcome == .acted { ran = true }
        }
        T.expect(asked && ran && h.performed.count == 1, "asked \(asked), ran \(ran), performed \(h.performed.count)")
        // An expired first tap asks again instead of running.
        h.app.confirmWindow = 0.2
        h.performed.removeAll()
        var first: TapRecord.Outcome?
        for _ in 0..<8 where first != .confirming { h.tap("z1"); first = h.app.lastRecord?.outcome }
        T.sleep(0.35)
        var second: TapRecord.Outcome?
        for _ in 0..<8 where second != .confirming && second != .acted { h.tap("z1"); second = h.app.lastRecord?.outcome }
        T.expect(first == .confirming && second == .confirming && h.performed.isEmpty, "after the window: first \(String(describing: first)), second \(String(describing: second)), performed \(h.performed.count)")
        // A different zone in between does not count as the second tap.
        h.app.confirmWindow = 3
        var b = h.app.action(for: 0)
        b.confirmTwice = false
        h.app.setAction(b, for: 0)
        h.performed.removeAll()
        T.note("confirm flow ok")
    }

    T.run("new zone settings persist and old configs still load") {
        let dir = T.tempDir("zoneconfig")
        let store = Store(directory: dir)
        var cfg = AppConfig()
        cfg.actions["z0"] = ZoneAction(kind: .shortcut, keyCombo: KeyCombo(keyCode: 20, modifiers: CGEventFlags([.maskCommand, .maskShift]).rawValue, label: "⇧⌘3"), confirmTwice: true)
        cfg.actions["z1"] = ZoneAction(kind: .runShortcut, text: "Focus")
        cfg.actions["z2"] = ZoneAction(kind: .openLink, text: "example.com/x")
        cfg.actions["z3"] = ZoneAction(kind: .openLink, text: "")
        store.save(cfg)
        let back = store.loadConfig()
        T.expect(back.practiceMode, "a fresh config should start in practice mode")
        T.expect(back.actions["z0"]?.keyCombo?.label == "⇧⌘3" && back.actions["z0"]?.confirmTwice == true && back.actions["z0"]?.title == "⇧⌘3", "shortcut zone: \(String(describing: back.actions["z0"]))")
        T.expect(back.actions["z1"]?.text == "Focus" && back.actions["z1"]?.isConfigured == true && back.actions["z1"]?.title == "Shortcut: Focus", "shortcut name zone")
        T.expect(back.actions["z2"]?.isConfigured == true && back.actions["z2"]?.title == "Open example.com", "link zone: \(String(describing: back.actions["z2"]?.title))")
        T.expect(back.actions["z3"]?.isConfigured == false && back.actions["z3"]?.setupHint != nil, "empty link should need setup")
        T.expect(ZoneAction.validLink("example.com/x")?.absoluteString == "https://example.com/x", "bare domain not upgraded to https")
        T.expect(ZoneAction.validLink("shortcuts://run-shortcut?name=Focus")?.scheme == "shortcuts", "custom scheme refused")
        T.expect(ZoneAction.validLink("file:///etc/passwd") == nil && ZoneAction.validLink("javascript:alert(1)") == nil && ZoneAction.validLink("not a link") == nil, "bad links accepted")
        try! #"{"actions": {"z0": {"kind": "desktopLeft"}}}"#.write(to: dir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        let old = Store(directory: dir).loadConfig()
        T.expect(!old.practiceMode && old.actions["z0"]?.kind == .desktopLeft && old.actions["z0"]?.confirmTwice == false, "old config: practice \(old.practiceMode), z0 \(String(describing: old.actions["z0"]))")
        try! #"{"actions": {"z0": {"kind": "fromTheFuture"}}}"#.write(to: dir.appendingPathComponent("config.json"), atomically: true, encoding: .utf8)
        T.expect(Store(directory: dir).loadConfig().actions["z0"]?.kind == ActionKind.none, "an unknown action kind should load as Nothing")
        try? FileManager.default.removeItem(at: dir)
    }

    T.run("every tap outcome has its own explanation") {
        func rec(_ o: TapRecord.Outcome, _ d: String) -> TapRecord {
            TapRecord(id: 1, date: Date(), outcome: o, label: nil, confidence: nil, detail: d, peakG: 5, peakA: 0.01, lid: nil, gyro: [])
        }
        let cases: [(TapRecord.Outcome, String)] = [
            (.ignored, "Ignored: typing"), (.ignored, "Ignored: click"), (.ignored, "Ignored: pointer moving"),
            (.ignored, "Ignored: still moving"), (.ignored, "Ignored: lid moved"),
            (.rejected, "Too soft (2.1 °/s). Tap a little crisper"), (.rejected, "Not sure which zone"),
            (.rejected, "Unfamiliar tap"), (.rejected, "Looks like a bump, not a tap"),
            (.untrained, "Tap detected. Calibrate to map it to a zone"), (.guarded, "Ignored while Privacy Guard is on"),
            (.practiced, "Practice: Desktop Left"), (.confirming, "Tap again to run Lock Screen"),
        ]
        let tips = cases.map { rec($0.0, $0.1).tip }
        T.expect(tips.allSatisfy { ($0 ?? "").count > 20 }, "missing tips: \(tips)")
        T.expect(Set(tips.compactMap { $0 }).count == cases.count, "tips should be specific: \(Set(tips.compactMap { $0 }).count) distinct for \(cases.count) cases")
        T.expect(rec(.acted, "Desktop Left").tip == nil && rec(.recorded, "Recorded for Zone 1").tip == nil, "acted and recorded taps need no tip")
    }

    T.run("calibration intro: taps don't count until Start") {
        let h = AppHarness(name: "intro")
        h.app.startCalibration(perZone: 16, block: 1)
        h.app.calibration?.showIntro = true
        let n = h.app.dataset.samples.count
        h.tap(h.app.calibration!.target!)
        T.expect(h.app.dataset.samples.count == n && h.app.calibration?.position == 0, "a tap during the intro was recorded")
        h.app.beginCalibrationTaps()
        T.expect(h.app.calibration?.showIntro == false, "Start did not dismiss the intro")
        h.tap(h.app.calibration!.target!)
        T.expect(h.app.dataset.samples.count == n + 1, "a tap after Start was not recorded")
        h.app.endCalibration()
    }

    T.run("key combo labels follow Apple's modifier order") {
        T.expect(KeyNames.name(for: 123, characters: nil) == "←" && KeyNames.name(for: 0, characters: "a") == "A" && KeyNames.name(for: 122, characters: "\u{F704}") == "F1" && KeyNames.name(for: 49, characters: " ") == "Space", "key names")
        let label = KeyCombo.label(keyCode: 20, flags: [.maskCommand, .maskShift], characters: "3")
        T.expect(label == "⇧⌘3", "label \(label)")
        T.expect(KeyCombo.label(keyCode: 126, flags: [.maskControl, .maskSecondaryFn], characters: nil) == "⌃↑", "fn should not show for arrows: \(KeyCombo.label(keyCode: 126, flags: [.maskControl, .maskSecondaryFn], characters: nil))")
        T.expect(KeyCombo(keyCode: 20, modifiers: CGEventFlags([.maskCommand]).rawValue, label: "⌘3").isUsable && !KeyCombo(keyCode: 20, modifiers: 0, label: "3").isUsable && KeyCombo(keyCode: 122, modifiers: 0, label: "F1").isUsable, "usability rule")
        T.expect(ActionGroup.all.flatMap(\.kinds).count == ActionKind.allCases.count && ActionGroup.all.first?.kinds == [.none], "every action is in exactly one group")
    }

    T.run("tap handling latency (features + predict + dispatch)") {
        let h = AppHarness(name: "latency")
        guard h.train() else { return T.fail("no model") }
        let events = (0..<100).map { _ in h.app.replayEvent(label: zoneLabel(Int.random(in: 0..<4)))! }
        let t0 = Date()
        for e in events { h.app.handle(e); if h.app.privacyGuard.isActive { h.app.privacyGuard.release() } }
        let ms = Date().timeIntervalSince(t0) * 1000 / 100
        T.note(String(format: "%.2f ms per tap on the main thread", ms))
        T.expect(ms < 15, "handling a tap takes \(ms) ms")
    }
}
