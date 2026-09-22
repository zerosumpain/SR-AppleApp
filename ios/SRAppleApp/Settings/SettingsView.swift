import SwiftUI

/// Everything the app can be told to do, and what it is costing to do it.
///
/// Built the way /health builds a page rather than as a list of toggles: the
/// measurement comes FIRST, because the question is not "what are the settings"
/// but "what is the right balance", and a row of sliders cannot answer that.
/// Section A is the instrument, B is the control, and the presets are there so
/// a combination of nine numbers has a name.
struct SettingsScreen: View {
    @ObservedObject var outbox: Outbox
    @ObservedObject var companion: Companion
    @ObservedObject var location: LocationCollector
    @ObservedObject var battery: BatteryMonitor
    @Environment(\.dismiss) private var dismiss

    @State private var draft = LocationSettings()
    @State private var loaded = false
    @State private var showAdvanced = false
    @State private var saved: String?

    private var dirty: Bool { draft != outbox.state.location }

    var body: some View {
        SRShell(
            path: "/settings",
            kicker: draft.matchingPreset?.label ?? "Custom",
            back: (label: "Done", action: { dismiss() }),
            footer: [
                "Strange Ramblings · companion settings",
                "Battery figures are DEVICE-WIDE — iOS does not report per-app use",
                "Changes apply at the next fix, not the next launch",
            ]
        ) {
            SRSection {
                SectionHead(
                    kicker: "A / What it is costing",
                    title: ["The balance,", "measured"],
                    strap: "iOS never tells an app its own share of the battery, so this is the whole device's drain while sharing was on, beside what that drain bought."
                )
                batteryDeck
            }

            SRSection(tinted: true) {
                SectionHead(
                    kicker: "B / Location",
                    title: ["How hard", "it looks"],
                    strap: "Pick a starting point, then change anything. The default reproduces exactly what the app did before this screen existed."
                )
                presets
            }

            SRSection {
                advanced
            }

            SRSection(tinted: true) {
                SectionHead(kicker: "C / Apple Health", title: ["What it", "uploads"], strap: nil)
                healthToggles
            }

            SRSection(isLast: true) {
                SectionHead(kicker: "D / Sync", title: ["Where it", "sends it"], strap: nil)
                syncInfo
            }
        }
        .task {
            guard !loaded else { return }
            draft = outbox.state.location
            loaded = true
        }
        .overlay(alignment: .bottom) {
            if dirty || saved != nil { saveBar }
        }
    }

    // MARK: - A. The instrument

    private var batteryDeck: some View {
        let samples = outbox.state.battery
        let sharingDrain = BatteryMaths.drainPerHour(samples, sharingOnly: true)
        let allDrain = BatteryMaths.drainPerHour(samples, sharingOnly: false)
        let hours = BatteryMaths.measuredHours(samples, sharingOnly: true)
        let points = outbox.state.pointsRecorded
        let meanAccuracy = points > 0 ? outbox.state.accuracySum / Double(points) : 0

        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 22) {
                Figure(value: sharingDrain.map { String(format: "%.1f%%", $0) } ?? "—",
                       label: "Drain/hour sharing")
                Figure(value: allDrain.map { String(format: "%.1f%%", $0) } ?? "—",
                       label: "Drain/hour overall")
            }
            HStack(alignment: .top, spacing: 22) {
                Figure(value: "\(points)", label: "Points recorded")
                Figure(value: points > 0 ? "±\(Int(meanAccuracy))m" : "—", label: "Mean accuracy")
            }

            // A figure with no frame is the documented failure, so say what the
            // number is standing on — and say plainly when it is standing on
            // nothing yet rather than printing a confident zero.
            if let sharingDrain, let allDrain {
                Text(sharingDrain > allDrain
                     ? String(format: "Sharing costs about %.1f%% an hour more than the phone's baseline.", sharingDrain - allDrain)
                     : "Sharing is not measurably above the phone's baseline drain.")
                    .font(SR.body(15))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(hours >= 1
                 ? String(format: "Measured over %.1f hours of sharing, charging time excluded.", hours)
                 : "Not enough evidence yet. A reading is taken every five minutes and at least an hour of discharge is needed before this says anything — below that the 1%% battery step is most of the signal.")
                .font(SR.mono(12))
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            if let since = outbox.state.countingSince {
                Text("Counting since \(since.formatted(date: .abbreviated, time: .shortened))")
                    .font(SR.mono(12))
                    .foregroundStyle(SR.inkGhost)
            }

            SRButton(title: "Reset the measurement") {
                try? outbox.change {
                    $0.battery = []
                    $0.pointsRecorded = 0
                    $0.accuracySum = 0
                    $0.countingSince = nil
                }
                saved = "Measurement reset. Change a preset and leave it a day."
            }
        }
    }

    // MARK: - B. Presets

    private var presets: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(LocationSettings.Preset.allCases) { preset in
                let current = draft.matchingPreset == preset
                Button {
                    draft = preset.settings
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(preset.label.uppercased())
                                .font(SR.monoMedium(12))
                                .tracking(1.2)
                                .foregroundStyle(current ? SR.accent : SR.ink)
                            Spacer()
                            if current { SRPill(text: "Selected", tone: SR.accent) }
                        }
                        Text(preset.detail)
                            .font(SR.body(14))
                            .foregroundStyle(SR.inkSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SR.paper)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("preset-\(preset.rawValue)")
            }
        }
        .background(SR.line)
        .overlay(Rectangle().strokeBorder(SR.line, lineWidth: 1))
    }

    // MARK: - B. Every individual value

    private var advanced: some View {
        VStack(alignment: .leading, spacing: 18) {
            Button { showAdvanced.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: showAdvanced ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                    Text("Every value".uppercased())
                        .font(SR.monoMedium(12))
                        .tracking(1.3)
                }
                .foregroundStyle(SR.inkSecondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("toggle-advanced")

            if showAdvanced {
                accuracyPicker("Accuracy while moving", selection: $draft.movingAccuracy)
                accuracyPicker("Accuracy while stopped", selection: $draft.stationaryAccuracy)

                stepperRow("Record every, moving", value: $draft.movingInterval,
                           range: 10...600, step: 10, unit: "s",
                           note: "How often a point is saved while you are moving.")
                stepperRow("Record every, stopped", value: $draft.stationaryInterval,
                           range: 60...3600, step: 60, unit: "s",
                           note: "Standing still rarely needs more than this.")
                stepperRow("Heartbeat", value: $draft.heartbeatInterval,
                           range: 0...1800, step: 60, unit: "s",
                           note: "Forces a fix on a timer while the app runs. THE biggest lever here — 0 turns it off and lets Core Location report when it has something.")
                stepperRow("Move after", value: $draft.movingDistanceFilter,
                           range: 5...500, step: 5, unit: "m",
                           note: "Metres before Core Location reports at all, while moving.")
                stepperRow("Move after, stopped", value: $draft.stationaryDistanceFilter,
                           range: 10...1000, step: 10, unit: "m", note: nil)
                stepperRow("Stopped after", value: $draft.stopThreshold,
                           range: 60...900, step: 30, unit: "s",
                           note: "Still for this long and the phone drops to the cheaper settings.")
                stepperRow("Discard fixes looser than", value: $draft.accuracyCeiling,
                           range: 50...1000, step: 50, unit: "m",
                           note: "A cheap accuracy setting produces loose fixes, so raise this with it or every point is thrown away.")

                activityPicker

                Toggle(isOn: $draft.pausesAutomatically) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Let iOS pause updates").font(SR.body(15)).foregroundStyle(SR.ink)
                        Text("Stops the radio when iOS decides nothing is happening.")
                            .font(SR.body(13)).foregroundStyle(SR.inkMuted)
                    }
                }.tint(SR.accent)

                Toggle(isOn: $draft.significantChangeMonitoring) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Significant-change recovery").font(SR.body(15)).foregroundStyle(SR.ink)
                        Text("Cheap, and the only thing that wakes the app after iOS suspends it. Turning it off saves almost nothing and loses background recovery.")
                            .font(SR.body(13)).foregroundStyle(SR.inkMuted)
                    }
                }.tint(SR.accent)
            }
        }
    }

    private func accuracyPicker(_ title: String, selection: Binding<LocationAccuracy>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SRLabel(text: title)
            Picker(title, selection: selection) {
                ForEach(LocationAccuracy.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(selection.wrappedValue.cost)
                .font(SR.body(13))
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var activityPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SRLabel(text: "What iOS thinks you are doing")
            Picker("Activity", selection: $draft.activity) {
                ForEach(LocationActivity.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            Text(draft.activity.cost)
                .font(SR.body(13))
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepperRow(_ title: String, value: Binding<Double>,
                            range: ClosedRange<Double>, step: Double,
                            unit: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Stepper(value: value, in: range, step: step) {
                HStack {
                    Text(title).font(SR.body(15)).foregroundStyle(SR.ink)
                    Spacer()
                    Text(value.wrappedValue == 0 ? "Off" : "\(Int(value.wrappedValue))\(unit)")
                        .font(SR.monoMedium(13))
                        .foregroundStyle(SR.accent)
                }
            }
            if let note {
                Text(note)
                    .font(SR.body(13))
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - C and D

    private var healthToggles: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(["steps", "heart_rate", "resting_heart_rate", "sleep", "workout"], id: \.self) { kind in
                Toggle(isOn: Binding(
                    get: { outbox.state.healthEnabled.contains(kind) },
                    set: { companion.setHealth(kind, enabled: $0) }
                )) {
                    Text(HealthCollector.labels[kind] ?? kind)
                        .font(SR.body(15)).foregroundStyle(SR.ink)
                }
                .tint(SR.accent)
                .disabled(companion.busy)
            }
            Text("Health is read on a schedule iOS controls, not on a timer of ours, so these cost far less than location. Turning one off stops future uploads; delete what is already there on the website.")
                .font(SR.body(13))
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
            SRButton(title: "Review Apple Health permissions",
                     disabled: companion.busy || outbox.state.healthEnabled.isEmpty) {
                Task { await companion.authorizeHealth() }
            }
        }
    }

    private var syncInfo: some View {
        VStack(alignment: .leading, spacing: 14) {
            Toggle(isOn: Binding(
                get: { outbox.state.sharing },
                set: { value in Task { await companion.setSharing(value) } }
            )) {
                Text("Share location with my family").font(SR.body(15)).foregroundStyle(SR.ink)
            }
            .tint(SR.accent)
            .disabled(companion.busy)

            Text(location.status)
                .font(SR.body(14))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 20) {
                Figure(value: "\(companion.queueCount)", label: "Waiting to upload")
                if let last = companion.lastUpload {
                    Figure(value: last.formatted(date: .omitted, time: .shortened), label: "Last upload")
                }
            }
        }
    }

    // MARK: - Saving

    private var saveBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let saved {
                Text(saved).font(SR.body(14)).foregroundStyle(SR.paper)
            } else {
                Text("Changed. Applies at the next fix.")
                    .font(SR.body(14)).foregroundStyle(SR.paper)
            }
            if dirty {
                HStack(spacing: 10) {
                    SRButton(title: "Apply", filled: true, register: .ink) { apply() }
                    SRButton(title: "Discard", register: .ink) { draft = outbox.state.location }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SR.ink)
        .padding(.horizontal, SR.gutter)
        .padding(.bottom, 10)
    }

    private func apply() {
        do {
            try outbox.change { $0.location = draft }
            // Push it at Core Location now. Waiting for the next launch is how a
            // battery setting appears not to work.
            location.applySettings()
            if outbox.state.sharing { location.start() }
            saved = "Applied. Leave it a few hours, then read section A again."
        } catch {
            saved = error.localizedDescription
        }
    }
}
