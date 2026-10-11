import SwiftUI

/// The gate, opening and closing, with what caused each move.
///
/// This is the monitoring half of the motion gate and it is not optional
/// furniture. An app that switches its own GPS off has exactly two possible
/// stories — "it slept all night and saved a fortune" and "it stopped recording
/// at nine and nobody noticed" — and from the outside they look the same. The
/// log is the only thing that tells them apart.
///
/// Built on /health's ledger: figures with the frame they are measured in, a
/// hairline table, and an explaining sentence in body font underneath rather
/// than a legend. The wake-quality figure is the one to read — it is the
/// evidence for the single most useful lever on the settings screen.
struct ActivityLogScreen: View {
    @ObservedObject var outbox: Outbox

    @State private var window = LogWindow.day
    @State private var cleared = false

    /// How far back the figures and the list look.
    enum LogWindow: String, CaseIterable, Identifiable {
        case day, week, all
        var id: String { rawValue }

        var label: String {
            switch self {
            case .day: return "24 hours"
            case .week: return "7 days"
            case .all: return "Everything"
            }
        }

        var seconds: TimeInterval? {
            switch self {
            case .day: return 24 * 3600
            case .week: return 7 * 24 * 3600
            case .all: return nil
            }
        }
    }

    private var since: Date {
        guard let seconds = window.seconds else { return .distantPast }
        return Date().addingTimeInterval(-seconds)
    }

    private var events: [GateEvent] {
        outbox.state.gateEvents.filter { $0.at >= since }.sorted { $0.at > $1.at }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
            SRSection {
                SectionHead(
                    kicker: "A / Duty cycle",
                    title: ["What the gate", "actually saved"],
                    strap: "How much of the measured period had GPS running. The gate can only save what it was awake to switch off, so time before the first line below is not counted at all."
                )
                windowPicker
                dutyDeck
            }

            SRSection(tinted: true) {
                SectionHead(
                    kicker: "B / Wakes",
                    title: ["Was it", "worth waking"],
                    strap: nil
                )
                wakeDeck
            }

            SRSection(isLast: true) {
                SectionHead(
                    kicker: "C / The log",
                    title: ["Every", "change"],
                    strap: nil
                )
                ledger
            }

            SRSection(isLast: true) {
                Text("Kept for the last \(GateEvent.maxStored) changes. Hours before the first line are not counted, not assumed.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .srPaper()
        .navigationTitle("Gate history")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - A

    private var windowPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Window", selection: $window) {
                ForEach(LogWindow.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier("log-window")
        }
        .padding(.bottom, 20)
    }

    private var dutyDeck: some View {
        let now = Date()
        let start = window.seconds == nil ? (outbox.state.gateEvents.first?.at ?? now) : since
        let spans = GateMaths.spans(outbox.state.gateEvents, since: start, now: now)
        let duty = GateMaths.dutyCycle(outbox.state.gateEvents, since: start, now: now)

        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 22) {
                Figure(value: duty.map { String(format: "%.0f%%", $0 * 100) } ?? "—",
                       label: "Of the time, GPS on")
                Figure(value: hours(spans.armed), label: "Asleep")
            }
            HStack(alignment: .top, spacing: 22) {
                Figure(value: hours(spans.tracking), label: "GPS on")
                Figure(value: "\(events.count)", label: "Changes logged")
            }

            // A figure with no frame is the documented failure, so say what this
            // one is standing on — and say plainly when it is standing on
            // nothing rather than printing a confident zero.
            Text(explanation(duty: duty, spans: spans))
                .font(SR.body(15))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if !outbox.state.location.motion.enabled {
                Text("The motion gate is off, so GPS never sleeps and this will read 100%. Turn it on in section C of the settings.")
                    .font(SR.mono(12))
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func explanation(duty: Double?, spans: (tracking: TimeInterval, armed: TimeInterval)) -> String {
        guard let duty else {
            return "Nothing logged in this window yet. The first line arrives when sharing is turned on."
        }
        if spans.armed <= 0 {
            return "GPS ran for the whole of this window. Either the gate is off, or it has not managed to sleep — check for a STAYED ON line below, which says what stopped it."
        }
        return String(format: "GPS ran for %.0f%% of the measured period and slept for the rest. Read that beside the drain figure on the settings screen: this is the share of time being paid for, not the saving itself.", duty * 100)
    }

    // MARK: - B

    private var wakeDeck: some View {
        let quality = GateMaths.wakeQuality(outbox.state.gateEvents, since: since)
        let blocked = GateMaths.count(outbox.state.gateEvents, kind: .blocked, since: since)

        return VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top, spacing: 22) {
                Figure(value: "\(quality.wakes)", label: "Woken")
                Figure(value: "\(quality.real)", label: "Worth waking")
                Figure(value: quality.share.map { String(format: "%.0f%%", $0 * 100) } ?? "—",
                       label: "Hit rate")
            }

            SRMeter(filled: Int(((quality.share ?? 0) * 5).rounded()),
                    label: "Wakes that found real movement")

            Text(wakeAdvice(quality))
                .font(SR.body(15))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if blocked > 0 {
                Text("\(blocked) time\(blocked == 1 ? "" : "s") the gate wanted to sleep and could not. The reason is on the row below — usually Always location access or Motion & Fitness being off, and until it is fixed the app is paying full price.")
                    .font(SR.body(14))
                    .foregroundStyle(SR.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func wakeAdvice(_ quality: (wakes: Int, real: Int, share: Double?)) -> String {
        guard let share = quality.share, quality.wakes >= 3 else {
            return "Not enough wakes yet to say. Three or four is the point at which this figure starts meaning something."
        }
        if share < 0.34 {
            return "Most wakes found nothing. The anchor is exiting itself — widen it in section C and the phone will be disturbed less. This is the lever worth moving first."
        }
        if share > 0.85 {
            return "Almost every wake found real movement, so the anchor is not costing anything. If you would rather hear about movement sooner, tighten it."
        }
        return "A reasonable balance: the phone wakes, checks the motion log for nothing, and goes back down — which is cheap, because checking costs no sensor time."
    }

    // MARK: - C

    private var ledger: some View {
        VStack(alignment: .leading, spacing: 18) {
            if events.isEmpty {
                Text("Nothing in this window.")
                    .font(SR.body(15))
                    .foregroundStyle(SR.inkMuted)
            } else {
                SRLedger {
                    ForEach(events) { event in
                        row(event)
                    }
                }
            }

            SRButton(title: cleared ? "Log cleared" : "Clear the log", disabled: events.isEmpty) {
                try? outbox.change { $0.gateEvents = [] }
                cleared = true
            }
            Text("Clearing resets the duty cycle above with it — the figures are derived from these lines, not stored separately.")
                .font(SR.mono(12))
                .foregroundStyle(SR.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(_ event: GateEvent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(event.at.formatted(date: .omitted, time: .shortened))
                    .font(SR.monoMedium(12))
                    .foregroundStyle(SR.ink)
                Text(event.at.formatted(.dateTime.day().month(.abbreviated)))
                    .font(SR.mono(12))
                    .foregroundStyle(SR.inkMuted)
            }
            .frame(width: 62, alignment: .leading)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(event.kind.label.uppercased())
                        .font(SR.monoMedium(12))
                        .tracking(1.1)
                        .foregroundStyle(tone(event.kind))
                    Spacer(minLength: 4)
                    if let battery = event.battery, battery >= 0 {
                        Text("\(Int(battery * 100))%")
                            .font(SR.mono(12))
                            .foregroundStyle(SR.inkMuted)
                    }
                }
                Text(event.reason)
                    .font(SR.body(14))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = event.detail {
                    Text(detail.uppercased())
                        .font(SR.mono(12))
                        .tracking(1)
                        .foregroundStyle(SR.inkMuted)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SR.paper)
        .accessibilityElement(children: .combine)
    }

    /// Orange is spending, olive is saving. The same two hues the site uses for
    /// a number going the wrong and right way, and never paired with each other
    /// on a chart — here they are on separate rows, which is fine.
    private func tone(_ kind: GateEvent.Kind) -> Color {
        switch kind {
        case .resumed, .started, .closeOn: return SR.accent
        case .armed, .slept, .closeOff: return SR.good
        case .blocked: return SR.error
        case .woke: return SR.accentInk
        case .stopped: return SR.inkMuted
        }
    }

    private func hours(_ seconds: TimeInterval) -> String {
        if seconds <= 0 { return "—" }
        if seconds < 3600 { return "\(Int((seconds / 60).rounded()))m" }
        return String(format: "%.1fh", seconds / 3600)
    }
}
