import Charts
import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable {
    case welcome, zones, training, detection, permissions, general
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .welcome: "hand.wave"
        case .zones: "rectangle.split.2x2"
        case .training: "chart.bar.xaxis"
        case .detection: "waveform.path.ecg"
        case .permissions: "lock.shield"
        case .general: "gearshape"
        }
    }
}

struct SettingsView: View {
    @AppStorage("settingsPane") private var storedPane = SettingsPane.zones.rawValue

    private var pane: Binding<SettingsPane?> {
        Binding(get: { SettingsPane(rawValue: storedPane) ?? .zones }, set: { storedPane = ($0 ?? .zones).rawValue })
    }

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, selection: pane) { p in
                Label(p.title, systemImage: p.symbol).tag(p)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 190, max: 220)
        } detail: {
            Group {
                switch pane.wrappedValue ?? .zones {
                case .welcome: WelcomePane()
                case .zones: ZonesPane()
                case .training: TrainingPane()
                case .detection: DetectionPane()
                case .permissions: PermissionsPane()
                case .general: GeneralPane()
                }
            }
            .formStyle(.grouped)
            .navigationTitle((pane.wrappedValue ?? .zones).title)
        }
    }
}

// MARK: - Zones

private struct ZonesPane: View {
    @Environment(AppModel.self) private var app
    @State private var selected = 0
    @State private var pendingGrid: Grid?
    @State private var choosingApp = false

    var body: some View {
        let current = app.action(for: selected)
        Form {
            Section {
                DisplayMap(grid: app.grid, action: app.action(for:), style: .large, selected: selected, ripple: app.ripple,
                           onSelect: { selected = $0 },
                           contextMenu: { zone in AnyView(ZoneActionMenu(zone: zone).environment(app)) })
                    .frame(maxWidth: 560)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            } footer: {
                Text("Click a zone to edit it. Zones are where you tap on your screen.")
                    .frame(maxWidth: .infinity, alignment: .center)
            }

            Section("Zone \(selected + 1)") {
                Picker("Action", selection: Binding(get: { current.kind }, set: { choose($0) })) {
                    ForEach(ActionGroup.all) { group in
                        Section(group.name) {
                            ForEach(group.kinds) { kind in
                                Label(kind.title, systemImage: kind.symbol).tag(kind)
                            }
                        }
                    }
                }
                Text(current.kind.detail)
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if current.kind == .openApp {
                    LabeledContent("App") {
                        HStack(spacing: 8) {
                            if current.appBundleID != nil { ActionGlyph(action: current, size: 14) }
                            Text(current.appName ?? "None chosen").foregroundStyle(current.appName == nil ? .secondary : .primary)
                            Button("Choose…") { choosingApp = true }
                        }
                    }
                }
                if current.kind == .shortcut {
                    LabeledContent("Keys") {
                        ShortcutRecorder(combo: Binding(get: { current.keyCombo }, set: { combo in update { $0.keyCombo = combo } }))
                    }
                    Text("Click Record, then press the combination: ⇧⌘4 for a screenshot, ⌘Space for Spotlight, or a shortcut you gave an app. Combinations macOS reserves for itself, such as ⌘Tab, can't be recorded.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if current.kind == .runShortcut {
                    LabeledContent("Shortcut name") {
                        HStack(spacing: 8) {
                            TextField("Exactly as named in the Shortcuts app", text: textBinding)
                                .textFieldStyle(.roundedBorder)
                                .frame(minWidth: 240)
                            Button("Open Shortcuts") { ActionRunner.openApp(bundleID: "com.apple.shortcuts", then: nil) }
                        }
                    }
                    Text("Anything a Shortcut can do, a tap can do: toggle a Focus, start a timer, run a script. It runs in the background; the first run may show a permission prompt from Shortcuts.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if current.kind == .openLink {
                    LabeledContent("Link") {
                        TextField("https://…", text: textBinding)
                            .textFieldStyle(.roundedBorder)
                            .frame(minWidth: 300)
                    }
                    if let t = current.text, !t.trimmingCharacters(in: .whitespaces).isEmpty, !current.isConfigured {
                        Label("Enter a full web address, or a link such as shortcuts://run-shortcut?name=Focus", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        Text("Opens in your default browser, or in the app that owns the link. LidTap itself never connects to anything.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                if current.kind != .none {
                    Toggle(isOn: Binding(get: { current.confirmTwice }, set: { on in update { $0.confirmTwice = on } })) {
                        Text("Tap twice to run")
                        Text("The first tap shows what would run; a second tap in the same zone within three seconds runs it. Good for anything you'd rather not trigger by accident.")
                    }
                }
                LabeledContent {
                    Button("Try It") { app.testAction(zone: selected) }
                        .disabled(current.kind == .none || !current.isConfigured)
                } label: {
                    Text("Runs this zone's action right now, so you can check it does what you expect.").foregroundStyle(.secondary)
                }
                if let hint = current.setupHint {
                    Label(hint, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                }
                if current.kind.needsAccessibility && !app.status.accessibility {
                    Label("Needs Accessibility. Allow it in Permissions.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }

            if current.kind == .privacyGuard { PrivacyGuardSection() }

            Section {
                Picker("Grid", selection: Binding(get: { app.grid }, set: { g in if g != app.grid { pendingGrid = g } })) {
                    ForEach(Grid.presets, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Layout")
            } footer: {
                Text("Fewer zones are more reliable. A new layout needs a new calibration.")
            }
        }
        .onAppear {
            if let z = app.settingsFocusZone, z < app.grid.count {
                selected = z
                app.settingsFocusZone = nil
                if app.settingsFocusPicksApp { choosingApp = true }
                app.settingsFocusPicksApp = false
            }
        }
        .onChange(of: app.grid) { selected = 0 }
        .alert("Switch to \(pendingGrid?.title ?? "")?", isPresented: Binding(get: { pendingGrid != nil }, set: { if !$0 { pendingGrid = nil } })) {
            Button("Cancel", role: .cancel) { pendingGrid = nil }
            Button("Switch and Calibrate") {
                if let g = pendingGrid { app.startCalibration(grid: g) }
                pendingGrid = nil
            }
        } message: {
            Text("The \(app.dataset.zoneTapCount) taps recorded for \(app.grid.title) will be replaced. Your bump examples are kept.")
        }
        .sheet(isPresented: $choosingApp) {
            AppPicker { info in
                app.setAction(ZoneAction(kind: .openApp, appBundleID: info.bundleID, appName: info.name), for: selected)
                choosingApp = false
            } cancel: { choosingApp = false }
        }
    }

    /// Picks a new kind for the selected zone, keeping its "tap twice" choice. Open App goes through the chooser.
    private func choose(_ kind: ActionKind) {
        if kind == .openApp { choosingApp = true; return }
        var a = ZoneAction(kind: kind)
        a.confirmTwice = app.action(for: selected).confirmTwice
        app.setAction(a, for: selected)
    }

    private func update(_ change: (inout ZoneAction) -> Void) {
        var a = app.action(for: selected)
        change(&a)
        app.setAction(a, for: selected)
    }

    private var textBinding: Binding<String> {
        Binding(get: { app.action(for: selected).text ?? "" }, set: { value in update { $0.text = value } })
    }
}

private struct PrivacyGuardSection: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Section {
            Toggle("Mute every microphone", isOn: $app.config.guardMutesMic)
            Toggle("Turn the camera off in meetings", isOn: $app.config.guardStopsCamera)
        } header: {
            Text("Privacy Guard")
        } footer: {
            Text("Hides every screen until you tap this zone again or click. Turns the camera off in Zoom, Microsoft Teams, Webex and Google Meet (Chrome, Edge, Brave or Safari), and turns it back on afterwards.")
        }
    }
}

struct AppPicker: View {
    let choose: (AppInfo) -> Void
    let cancel: () -> Void
    @State private var apps: [AppInfo] = []
    @State private var query = ""
    @State private var selection: String?

    var body: some View {
        let filtered = apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        VStack(spacing: 0) {
            List(selection: $selection) {
                let running = filtered.filter(\.isRunning), other = filtered.filter { !$0.isRunning }
                if !running.isEmpty { Section("Running") { ForEach(running) { row($0) } } }
                if !other.isEmpty { Section("Applications") { ForEach(other) { row($0) } } }
            }
            .searchable(text: $query, placement: .toolbar, prompt: "Search apps")
            .overlay { if !apps.isEmpty && filtered.isEmpty { ContentUnavailableView.search(text: query) } }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", action: cancel).keyboardShortcut(.cancelAction)
                Button("Choose") { if let s = selection, let info = apps.first(where: { $0.id == s }) { choose(info) } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selection == nil)
            }
            .padding(12)
        }
        .frame(width: 420, height: 520)
        .navigationTitle("Choose an App")
        .task { apps = AppCatalog.load() }
    }

    private func row(_ info: AppInfo) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: info.icon).resizable().frame(width: 22, height: 22)
            Text(info.name)
        }
        .tag(info.id)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { choose(info) }
    }
}

// MARK: - Training

private struct TrainingPane: View {
    @Environment(AppModel.self) private var app
    @State private var confirmDeleteAll = false

    var body: some View {
        @Bindable var app = app
        Form {
            Section {
                LabeledContent("Accuracy") {
                    Text(app.accuracy.map { "\(Int(($0 * 100).rounded()))% of taps land in the right zone" } ?? "Not trained yet")
                        .foregroundStyle(app.accuracy == nil ? .secondary : .primary)
                }
                LabeledContent("Recorded") {
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(app.dataset.zoneTapCount - app.softTapCount) taps, \(app.count(for: noiseLabel)) bumps")
                        if app.softTapCount > 0 {
                            Text(String(format: "%d softer than %.1f °/s, not used", app.softTapCount, app.config.minTapStrength))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Picker("Recogniser", selection: $app.config.modelChoice) {
                    Text("Automatic").tag("auto")
                    Divider()
                    ForEach(ModelKind.allCases) { Text($0.title).tag($0.rawValue) }
                }
                LabeledContent {
                    HStack {
                        Slider(value: snapped($app.config.minConfidence, 0.05), in: 0.3...0.95)
                        Text("\(Int((app.config.minConfidence * 100).rounded()))%").monospacedDigit().frame(width: 36, alignment: .trailing)
                    }
                } label: {
                    Text("Act only when this sure")
                    Text("Below this, LidTap shows \"Not sure which zone\" instead of guessing.")
                }
                LabeledContent {
                    HStack {
                        Slider(value: snapped($app.config.rejectFactor, 0.1), in: 1...5)
                        Text(String(format: "%.1f×", app.config.rejectFactor)).monospacedDigit().frame(width: 36, alignment: .trailing)
                    }
                } label: {
                    Text("Ignore unfamiliar taps")
                    Text("Lower is stricter: fewer wrong actions, more \"tap again\".")
                }
            } header: {
                Text("Recognition")
            } footer: {
                HStack {
                    if app.isTraining { ProgressView().controlSize(.small); Text("Learning your taps…") }
                    Spacer()
                    Button("Reset") {
                        app.config.modelChoice = "auto"
                        app.config.minConfidence = AppConfig().minConfidence
                        app.config.rejectFactor = AppConfig().rejectFactor
                    }
                    .help("Back to the defaults: automatic recogniser, 60% confidence, 2.0× unfamiliar")
                    Button("Retrain") { app.retrain() }.disabled(app.isTraining)
                    Button("Calibrate…") { app.startCalibration() }
                }
            }

            if let report = app.report {
                Section {
                    DisplayMap(grid: app.grid, action: app.action(for:), style: .large, reliability: report.zoneReliability)
                        .frame(maxWidth: 520)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                } header: {
                    Text("Reliability by zone")
                } footer: {
                    Text("How often a tap in each zone was recognised as that zone, scored on taps the recogniser never saw. Add taps to a weak zone, or use fewer zones.")
                }

                Section("Reliability by layout") { layoutTable(report) }
                if report.confusion != nil { Section("Where taps go") { confusion(report) } }
                if !report.learning.isEmpty {
                    Section {
                        learning(report)
                    } header: {
                        Text("Taps needed")
                    } footer: {
                        Text("Accuracy against the number of taps per zone used for learning. A flat curve means more taps won't help much.")
                    }
                }
            } else {
                Section {
                    ContentUnavailableView {
                        Label("Nothing learned yet", systemImage: "hand.tap")
                    } description: {
                        Text("Calibrate to record a few taps in each zone. Results appear here.")
                    } actions: {
                        Button("Calibrate…") { app.startCalibration() }.buttonStyle(.borderedProminent)
                    }
                }
            }

            Section {
                ForEach((0..<app.grid.count).map(zoneLabel) + [noiseLabel], id: \.self) { label in
                    let n = app.usableCount(for: label)
                    LabeledContent {
                        HStack(spacing: 10) {
                            Text("\(n)").monospacedDigit().foregroundStyle(.secondary)
                            Button(role: .destructive) { app.deleteSamples(label: label) } label: { Image(systemName: "trash") }
                                .buttonStyle(.borderless)
                                .disabled(n == 0)
                                .help("Delete these taps")
                        }
                    } label: {
                        if label == noiseLabel {
                            Label("Bumps", systemImage: "waveform.badge.minus")
                        } else {
                            Label { Text("Zone \((zoneIndex(label) ?? 0) + 1)") } icon: { ActionGlyph(action: app.action(for: zoneIndex(label) ?? 0), size: 12) }
                        }
                    }
                }
            } header: {
                Text("Recorded taps")
            } footer: {
                HStack { Spacer(); Button("Delete All…", role: .destructive) { confirmDeleteAll = true }.disabled(app.dataset.samples.isEmpty) }
            }
        }
        .confirmationDialog("Delete all \(app.dataset.samples.count) recorded taps?", isPresented: $confirmDeleteAll) {
            Button("Delete All Taps", role: .destructive) { app.clearData() }
        } message: {
            Text("LidTap will stop recognising zones until you calibrate again.")
        }
    }

    private func layoutTable(_ report: ModelReport) -> some View {
        SwiftUI.Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 8) {
            GridRow {
                Text("Recogniser").foregroundStyle(.secondary)
                ForEach(report.layouts, id: \.self) { Text($0).foregroundStyle(.secondary).gridColumnAlignment(.trailing) }
            }
            .font(.caption)
            Divider()
            ForEach(report.scores) { score in
                GridRow {
                    HStack(spacing: 4) {
                        Text(score.kind.title)
                        if score.kind == app.activeKind { Text("in use").font(.caption).foregroundStyle(.secondary) }
                    }
                    ForEach(report.layouts, id: \.self) { layout in
                        let v = score.accuracy[layout]
                        Text(v.map { "\(Int(($0 * 100).rounded()))%" } ?? "–")
                            .monospacedDigit()
                            .foregroundStyle(v.map { $0 < 0.75 ? Color.red : $0 < 0.9 ? Color.orange : Color.primary } ?? .secondary)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func confusion(_ report: ModelReport) -> some View {
        let cm = report.confusion ?? []
        let short = report.labels.map { $0 == noiseLabel ? "Bump" : "\((zoneIndex($0) ?? 0) + 1)" }
        return VStack(alignment: .leading, spacing: 8) {
            SwiftUI.Grid(horizontalSpacing: 3, verticalSpacing: 3) {
                GridRow {
                    Text("Tapped ↓  Read as →").font(.caption2).foregroundStyle(.secondary).gridCellColumns(1)
                    ForEach(short.indices, id: \.self) { Text(short[$0]).font(.caption).foregroundStyle(.secondary).frame(width: 34) }
                }
                ForEach(cm.indices, id: \.self) { i in
                    let total = max(cm[i].reduce(0, +), 1)
                    GridRow {
                        Text(i < short.count ? (short[i] == "Bump" ? "Bump" : "Zone \(short[i])") : "").font(.caption).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        ForEach(cm[i].indices, id: \.self) { j in
                            let v = cm[i][j], share = Double(v) / Double(total)
                            Text(v == 0 ? "" : "\(v)")
                                .font(.caption.weight(.medium)).monospacedDigit()
                                .frame(width: 34, height: 26)
                                .background((i == j ? Color.accentColor : Color.red).opacity(v == 0 ? 0.05 : 0.15 + share * 0.6),
                                            in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                                .foregroundStyle(share > 0.5 ? Color.white : Color.primary)
                        }
                    }
                }
            }
            Text("The diagonal is correct. Anything off it is a tap read as another zone.").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func learning(_ report: ModelReport) -> some View {
        Chart(report.learning, id: \.n) { p in
            LineMark(x: .value("Taps per zone", p.n), y: .value("Accuracy", p.accuracy))
                .interpolationMethod(.monotone)
            PointMark(x: .value("Taps per zone", p.n), y: .value("Accuracy", p.accuracy))
        }
        .foregroundStyle(Color.accentColor)
        .chartYScale(domain: 0...1)
        .chartYAxis { AxisMarks(values: [0, 0.5, 0.75, 0.9, 1]) { v in
            AxisGridLine()
            AxisValueLabel { Text("\(Int((v.as(Double.self) ?? 0) * 100))%") }
        } }
        .chartXAxisLabel("Taps per zone")
        .frame(height: 160)
        .padding(.vertical, 6)
    }
}

/// Snaps a slider's value to `step` without asking macOS to draw a tick per step.
func snapped(_ b: Binding<Double>, _ step: Double) -> Binding<Double> {
    Binding(get: { b.wrappedValue }, set: { b.wrappedValue = ($0 / step).rounded() * step })
}

// MARK: - Detection

private struct DetectionPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Form {
            Section {
                MotionTrace(detector: app.detector, seconds: 5, showsAxes: true)
                    .frame(height: 170)
                    .padding(.vertical, 4)
            } header: {
                Text("Live motion")
            } footer: {
                HStack(spacing: 14) {
                    Text(String(format: "%.0f Hz", app.status.rate))
                    Text(String(format: "Noise %.2f °/s", app.status.noise))
                    Text(String(format: "Trigger %.2f °/s", app.status.threshold))
                    if let lid = app.status.lid { Text("Lid \(lid)°") }
                    Spacer()
                    Text("A tap fires when the line crosses the dashed trigger.")
                }
                .monospacedDigit()
            }

            Section {
                slider("Minimum tap strength", "Softer taps are not recorded or acted on. Lower it only if crisp taps are being refused", $app.config.minTapStrength, 1.5...10, 0.5) { String(format: "%.1f °/s", $0) }
                slider("Trigger", "How far above the resting noise a tap must rise", $app.config.detector.k, 2...15, 0.5) { String(format: "%.1f× noise", $0) }
                slider("Minimum", "Raise if bumps register as taps. Lower if gentle taps are missed", $app.config.detector.minThreshold, 0.3...20, 0.1) { String(format: "%.1f °/s", $0) }
                slider("Gap between taps", "Shorter allows quicker repeat taps", $app.config.detector.refractory, 0.15...1, 0.05) { String(format: "%.2f s", $0) }
                slider("Pause after typing", "Taps this soon after a key, click or scroll are ignored", $app.config.detector.gateSeconds, 0...1, 0.05) { String(format: "%.2f s", $0) }
                Toggle(isOn: $app.config.detector.gating) {
                    Text("Ignore taps while typing or moving the lid")
                    Text("Keeps keystrokes, clicks and lid adjustments from counting as taps.")
                }
            } header: {
                Text("Sensitivity")
            } footer: {
                HStack {
                    Text("The defaults suit most Macs. Change one thing at a time and watch the trace.")
                    Spacer()
                    Button("Reset to Defaults") {
                        app.config.detector = DetectorSettings()
                        app.config.minTapStrength = AppConfig().minTapStrength
                    }
                }
            }

            Section("Recent taps") {
                if let last = app.lastRecord {
                    TapWaveform(gyro: last.gyro).frame(height: 56)
                    if let tip = last.tip {
                        Label {
                            Text(tip).font(.callout).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "lightbulb")
                        }
                        .foregroundStyle(.secondary)
                    }
                    ForEach(app.recent.prefix(8)) { r in
                        LabeledContent {
                            HStack(spacing: 10) {
                                if let c = r.confidence { Text("\(Int((c * 100).rounded()))%").monospacedDigit().foregroundStyle(.secondary) }
                                Text(r.date, format: .dateTime.hour().minute().second()).monospacedDigit().foregroundStyle(.tertiary)
                            }
                        } label: {
                            Text(r.label.flatMap(zoneIndex).map { "Zone \($0 + 1) · \(r.detail)" } ?? r.detail).lineLimit(1)
                        }
                    }
                } else {
                    Text("No taps yet. Tap your screen gently and watch the trace above.").foregroundStyle(.secondary)
                }
            }
        }
    }

    private func slider(_ title: String, _ help: String, _ value: Binding<Double>, _ range: ClosedRange<Double>, _ step: Double,
                        _ format: @escaping (Double) -> String) -> some View {
        LabeledContent {
            HStack {
                Slider(value: snapped(value, step), in: range)
                Text(format(value.wrappedValue)).monospacedDigit().frame(width: 82, alignment: .trailing)
            }
        } label: {
            Text(title)
            Text(help)
        }
    }
}

// MARK: - Permissions

private struct PermissionsPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        Form {
            Section {
                row("Motion sensor", "gyroscope",
                    ok: app.status.rate > 500,
                    detail: app.status.error ?? (app.status.rate > 500 ? String(format: "Streaming at %.0f Hz", app.status.rate) : "Not streaming yet. If it stays this way, allow Input Monitoring."),
                    button: nil)
                row("Accessibility", "accessibility",
                    ok: app.status.accessibility,
                    detail: "To switch desktops, control music, start a note and turn meeting cameras off.",
                    button: ("Allow…", { Permissions.requestAccessibility(); Permissions.openPrivacyPane("Privacy_Accessibility") }))
                row("Input Monitoring", "keyboard",
                    ok: app.status.rate > 500,
                    detail: "Some Macs need it before the motion sensor streams.",
                    button: ("Open…", { Permissions.openPrivacyPane("Privacy_ListenEvent") }))
                row("Automation", "safari",
                    ok: nil,
                    detail: "Asked the first time Privacy Guard looks for a Google Meet tab in your browser.",
                    button: ("Open…", { Permissions.openPrivacyPane("Privacy_Automation") }))
            } footer: {
                Text("LidTap runs entirely on this Mac. After installing a new build, macOS may ask you to switch Accessibility off and on again.")
            }
        }
    }

    private func row(_ title: String, _ symbol: String, ok: Bool?, detail: String, button: (String, () -> Void)?) -> some View {
        LabeledContent {
            HStack(spacing: 10) {
                if let ok {
                    Label(ok ? "On" : "Off", systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(ok ? .green : .orange)
                        .labelStyle(.titleAndIcon)
                }
                if let (label, action) = button { Button(label, action: action) }
            }
        } label: {
            Label {
                Text(title)
                Text(detail)
            } icon: {
                Image(systemName: symbol)
            }
        }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Form {
            Section {
                Toggle("LidTap is on", isOn: $app.config.enabled)
                Toggle("Open at login", isOn: Binding(get: { app.launchAtLogin }, set: { app.setLaunchAtLogin($0) }))
            }
            Section {
                Toggle(isOn: $app.config.practiceMode) {
                    Text("Practice mode")
                    Text("Taps show which zone they hit and nothing runs. On after a fresh install; also handy whenever you want to check what LidTap sees.")
                }
            }
            Section {
                Toggle(isOn: $app.config.showTapFeedback) {
                    Text("Show each tap on screen")
                    Text("A ripple in the zone you tapped, with the action's name.")
                }
                Toggle("Play sounds", isOn: $app.config.playSounds)
            } header: {
                Text("Feedback")
            }
            Section {
                LabeledContent("Help") {
                    Button("Show Welcome") { app.showSettings(pane: SettingsPane.welcome.rawValue) }
                }
                LabeledContent("Data") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.dataDirectory]) }
                }
            } footer: {
                Text("Tap gently with a fingertip. LidTap feels the whole laptop move, so there's never a need to press: pressing hard on a display can leave marks.")
            }
            Section {
                LabeledContent("Based on", value: "LidTap by Yemcube (Instagram @yem.cube)")
                LabeledContent("License", value: "LidTap License: MIT with attribution; commercial use by permission")
            } header: {
                Text("About")
            } footer: {
                Text("Built from source for private use. If you share anything based on this app, credit \"Based on LidTap by Yemcube\" with a link to instagram.com/yem.cube.")
            }
        }
    }
}

// MARK: - Welcome

/// First-run checklist with live status, and the explanations people otherwise have to find in the README.
private struct WelcomePane: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let sensorOn = app.status.rate > 500
        let sensorDetail: String = app.status.error
            ?? (sensorOn ? String(format: "Streaming at %.0f Hz.", app.status.rate) : "Starting. If it stays off, allow Input Monitoring in Permissions.")
        let accessibilityButton: (String, () -> Void)? = app.status.accessibility ? nil
            : ("Allow…", { Permissions.requestAccessibility(); Permissions.openPrivacyPane("Privacy_Accessibility") })
        let calibrationDetail: String = app.isTrained
            ? "\(app.dataset.zoneTapCount) taps recorded on \(app.grid.title)" + (app.accuracy.map { String(format: ", %.0f%% land in the right zone.", $0 * 100) } ?? ".")
            : "About two minutes: tap each zone a few times so LidTap learns your Mac, then let it hear 20 seconds of typing and bumps."
        let calibrateButton: (String, () -> Void)? = (app.isTrained ? "Calibrate Again…" : "Calibrate…", { app.startCalibration() })
        let practiceButton: (String, () -> Void)? = app.isTrained && app.config.practiceMode ? ("Turn On Actions", { app.config.practiceMode = false }) : nil
        Form {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Tap your screen. LidTap does the rest.").font(.title2.weight(.semibold))
                    Text("A light tap on the lid twists the whole laptop a tiny amount. The motion sensor in the base feels that twist, and LidTap learns what a tap in each zone of your screen feels like on your Mac. Everything happens on this Mac; nothing is sent anywhere.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 4)
            }

            Section("Get set up") {
                step(1, "Motion sensor", symbol: "gyroscope", done: sensorOn, detail: sensorDetail, button: nil)
                step(2, "Accessibility", symbol: "accessibility", done: app.status.accessibility,
                     detail: "Lets LidTap press the keys behind Desktop Left and Right, media keys, Lock Screen and your own shortcuts. macOS asks you; LidTap can't grant it itself.",
                     button: accessibilityButton)
                step(3, "Calibrate", symbol: "scope", done: app.isTrained, detail: calibrationDetail, button: calibrateButton)
                step(4, "Practise, then turn actions on", symbol: "graduationcap", done: app.isTrained && !app.config.practiceMode,
                     detail: "In practice mode every tap shows the zone it hit and nothing runs. When the readings look right, turn actions on.",
                     button: practiceButton)
            }

            Section("Good taps") {
                bullet("hand.point.up.left", "A quick, light flick with a fingertip, near the corner dot you calibrated on. Never press: force gains nothing and can mark the display.")
                bullet("timer", "Wait about half a second between taps.")
                bullet("hand.raised.slash", "Hands off the keyboard and trackpad: a click, a scroll or a moving pointer makes LidTap ignore the tap on purpose.")
                bullet("laptopcomputer", "Same desk and lid angle as when you calibrated. Moving to the sofa? Add a few taps there with Calibrate Again.")
            }

            Section("What each tap tells you") {
                outcome("checkmark.circle.fill", Color.green, "Ran", "The zone was recognised and its action ran.")
                outcome("graduationcap.fill", Color.blue, "Practice", "Recognised; nothing ran because practice mode is on.")
                outcome("hand.tap.fill", Color.orange, "Tap again", "This zone asks for a second tap within three seconds.")
                outcome("questionmark.circle.fill", Color.orange, "Not sure", "Below the confidence floor, or unlike anything recorded, so LidTap did nothing rather than guess.")
                outcome("minus.circle.fill", Color.secondary, "Ignored", "Typing, a click, a moving pointer or a moving lid right around the tap. The menu bar panel says which, and what to do.")
            }

            Section("If something's off") {
                bullet("questionmark.circle", "Taps say \"Not sure\": tap closer to the calibration dot, or add taps to that zone in Training.")
                bullet("speaker.slash", "Taps say \"Too soft\": flick a little more crisply. If good taps are still refused, lower the minimum in Detection.")
                bullet("waveform.path.ecg", "Nothing happens at all: open the menu bar panel. It shows the last tap and why, and Detection shows the live motion trace.")
                bullet("arrow.counterclockwise", "After reinstalling, switch LidTap off and on again under Privacy & Security › Accessibility: macOS ties the grant to each build.")
                bullet("hand.raised", "Want it quiet for a while? The switch at the top of the menu bar panel pauses it.")
            }

            Section {
                LabeledContent("Based on", value: "LidTap by Yemcube (Instagram @yem.cube)")
            } footer: {
                Text("Free for private use under the LidTap License. Share anything based on it with that credit, and ask the author before any commercial use.")
            }
        }
    }

    private func step(_ n: Int, _ title: String, symbol: String, done: Bool, detail: String, button: (String, () -> Void)?) -> some View {
        LabeledContent {
            HStack(spacing: 10) {
                Label(done ? "Done" : "To do", systemImage: done ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(done ? Color.green : Color.secondary)
                    .labelStyle(.titleAndIcon)
                if let (label, action) = button { Button(label, action: action) }
            }
        } label: {
            Label {
                Text("\(n). \(title)")
                Text(detail)
            } icon: {
                Image(systemName: symbol)
            }
        }
    }

    private func bullet(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
    }

    private func outcome(_ symbol: String, _ color: Color, _ name: String, _ text: String) -> some View {
        Label {
            (Text(name).bold() + Text(": " + text)).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
    }
}
