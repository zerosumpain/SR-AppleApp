import SwiftUI

// MARK: - Overnight vitals, Watch beside strap

/// Resting HR, breathing rate, blood oxygen and temperature as both devices
/// read them overnight — `HubDigest.vitals`, from /health's section C.
///
/// Two columns, never one number: the site's rule is that the Watch and the
/// strap are each read against their OWN history and never averaged, so the
/// phone shows the pair and the server's sentence about how far apart they
/// usually sit. Temperature arrives as a change from each device's own
/// baseline — wrist and skin are 2.6 °C apart, so two absolutes side by side
/// would read as a disagreement that is only a different place on the arm.
/// Every string is the server's; the phone decides nothing.
struct OvernightVitalsSection: View {
    let vitals: HubDigest.Vitals

    var body: some View {
        Section {
            ForEach(vitals.rows) { row in
                VitalPairCard(row: row).srBareRow()
            }
        } header: {
            SRSectionLabel(text: "Overnight vitals", trailing: "Watch · WHOOP")
        } footer: {
            if !vitals.note.isEmpty {
                Text(vitals.note)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 4)
            }
        }
    }
}

/// One vital: the Watch's reading and the strap's, then how they agree.
struct VitalPairCard: View {
    let row: HubDigest.Vitals.Row

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(row.label.uppercased())
                    .font(SR.Text.label())
                    .tracking(1.2)
                    .foregroundStyle(SR.inkMuted)
                Spacer(minLength: 8)
                if row.disagree != nil {
                    // A word with the colour, always: the dot alone is not a reading.
                    Text("APART")
                        .font(SR.Text.label())
                        .tracking(1.2)
                        .foregroundStyle(row.tone.color)
                }
            }

            // Side by side while they fit; stacked at the large accessibility
            // sizes rather than shrinking the figures.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) { columns }
                VStack(alignment: .leading, spacing: 14) { columns }
            }

            if let agreement = row.agreement {
                Text(agreement)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let disagree = row.disagree {
                Text(disagree)
                    .font(SR.Text.secondary())
                    .foregroundStyle(row.tone.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SR.cardPadding)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("health-vital-\(row.key)")
    }

    @ViewBuilder private var columns: some View {
        VitalColumn(device: "Apple Watch", short: "WATCH", reading: row.apple)
        VitalColumn(device: "WHOOP", short: "WHOOP", reading: row.whoop)
    }

    private var spoken: String {
        func part(_ device: String, _ r: HubDigest.Vitals.Reading?) -> String {
            guard let r else { return "\(device), no reading" }
            return "\(device) \(r.displayWithUnit), \(r.baseline)" + (r.asOf.map { ", as of \(VitalColumn.day($0))" } ?? "")
        }
        return [
            row.label,
            part("Apple Watch", row.apple),
            part("WHOOP", row.whoop),
            row.agreement,
            row.disagree.map { "Apart: \($0)" },
        ].compactMap { $0 }.joined(separator: ". ")
    }
}

/// One device's half of a pair.
struct VitalColumn: View {
    let device: String
    let short: String
    let reading: HubDigest.Vitals.Reading?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(short)
                .font(SR.Text.mono())
                .tracking(1.2)
                .foregroundStyle(SR.inkMuted)
            if let reading {
                Text(reading.displayWithUnit)
                    .font(SR.Text.figure(26))
                    .foregroundStyle(SR.ink)
                    .lineLimit(1)
                Text(reading.asOf.map { "\(reading.baseline) · as of \(Self.day($0))" } ?? reading.baseline)
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if reading.series.count > 1 {
                    SRSparkline(values: reading.series)
                        .frame(height: 28)
                        .padding(.top, 4)
                }
            } else {
                // A missing reading is a dash, never a zero.
                Text("—")
                    .font(SR.Text.figure(26))
                    .foregroundStyle(SR.inkGhost)
                Text("No reading")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// "2026-09-03" → "3 Sep". The server sends the date only when it is stale.
    static func day(_ iso: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_GB_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: iso) else { return iso }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_GB")
        out.dateFormat = "d MMM"
        return out.string(from: date)
    }
}

// MARK: - Sleep analytics

/// The Health tab's fifth area: the night, as /health reads it.
///
/// Its own screen rather than sections on the tab, so the tab stays the answer
/// to "how am I doing" and the night is one push away. Top to bottom: last
/// night (WHOOP's staging beside the Watch's total), the week from both, the
/// overnight vitals, then what /health concludes about sleep — balance,
/// regularity, circadian drift, the sleep-balance tripwire and the forecast.
/// Every figure and sentence is the hub digest's; the tab already loaded it,
/// and a pull here refreshes it.
struct SleepAnalyticsScreen: View {
    @ObservedObject var hub: HealthHubStore

    /// /health's sleep instruments, in the order the page reads them.
    static let instrumentKeys = ["balance", "sri", "circadian"]

    var body: some View {
        List {
            if let digest = hub.hub {
                content(digest)
            } else if hub.loading {
                HStack { Spacer(); ProgressView().tint(SR.accent); Spacer() }
                    .padding(.vertical, 40)
                    .srBareRow()
            } else {
                SREmpty(
                    title: hub.failed ? "Health is not answering" : "No sleep read yet",
                    icon: "moon.zzz",
                    message: hub.failed ? "The read did not load. Pull to try again." : "Last night appears here once the WHOOP strap or the Watch has synced it."
                )
                .srBareRow()
            }
        }
        .listStyle(.insetGrouped)
        .srGround(.vital)
        .navigationTitle("Sleep analytics")
        .navigationBarTitleDisplayMode(.inline)
        .srRefreshable { await hub.load(fresh: true) }
        .accessibilityIdentifier("sleep-analytics")
    }

    @ViewBuilder
    private func content(_ digest: HubDigest) -> some View {
        let sleep = digest.sleep
        let instruments = Self.instrumentKeys.compactMap { key in digest.instruments.first { $0.key == key } }
        let balance = digest.tripwires.first { $0.key == "sleep-balance" }
        let forecast = digest.forecasts.first { $0.key == "sleep" }

        if let night = sleep?.lastNight {
            Section {
                SleepLastNightCard(night: night).srBareRow()
            } header: {
                SRSectionLabel(text: "Last night", trailing: SleepFormat.day(night.date))
            }
        }

        if let nights = sleep?.nights, !nights.isEmpty {
            Section {
                SleepWeekCard(nights: nights).srBareRow()
            } header: {
                SRSectionLabel(text: "The week", trailing: "WHOOP · Watch")
            } footer: {
                if let note = sleep?.note, !note.isEmpty {
                    Text(note)
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.vertical, 4)
                }
            }
        }

        if let vitals = digest.vitals, !vitals.rows.isEmpty {
            OvernightVitalsSection(vitals: vitals)
        }

        if !instruments.isEmpty || balance != nil || forecast != nil {
            Section {
                ForEach(instruments) { InstrumentRow(instrument: $0).srGlassRow() }
                if let balance { TripwireRow(tripwire: balance).srGlassRow() }
                if let forecast { ForecastCard(forecast: forecast).srBareRow() }
            } header: {
                SRSectionLabel(text: "What /health reads")
            }
        }

        if sleep == nil && digest.vitals == nil && instruments.isEmpty {
            SREmpty(title: "No sleep read yet", icon: "moon.zzz",
                    message: "Last night appears here once the WHOOP strap or the Watch has synced it.")
                .srBareRow()
        }
    }
}

enum SleepFormat {
    /// "2026-09-23" → "Tue 23 Sep".
    static func day(_ iso: String) -> String {
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_GB_POSIX")
        parser.dateFormat = "yyyy-MM-dd"
        guard let date = parser.date(from: String(iso.prefix(10))) else { return iso }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_GB")
        out.dateFormat = "EEE d MMM"
        return out.string(from: date)
    }

    /// 7.08 → "7h05m"; nil → "—".
    static func hours(_ value: Double?) -> String {
        guard let value, value > 0 else { return "—" }
        let minutes = Int((value * 60).rounded())
        return "\(minutes / 60)h\(String(format: "%02d", minutes % 60))m"
    }

    /// The stage's colour in the bar. Each also has its word in the legend.
    static func color(_ key: String) -> Color {
        switch key {
        case "deep": return SR.accentDeep
        case "rem": return SR.accent
        case "light": return SR.accent.opacity(0.45)
        default: return SR.inkGhost
        }
    }
}

/// WHOOP's night: asleep and performance, the Watch's total beside it, the
/// stages as one bar with a legend, and what else the strap noticed.
struct SleepLastNightCard: View {
    let night: HubDigest.Sleep.LastNight

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 16) { figures }
                VStack(alignment: .leading, spacing: 12) { figures }
            }

            let total = max(night.stages.reduce(0) { $0 + $1.minutes }, 1)
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(night.stages) { stage in
                        SleepFormat.color(stage.key)
                            .frame(width: max(0, (geo.size.width - 6) * stage.minutes / total))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .frame(height: 12)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(night.stages) { stage in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 2).fill(SleepFormat.color(stage.key)).frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        Text(stage.label).font(SR.Text.bodyMedium(15)).foregroundStyle(SR.ink)
                        Spacer(minLength: 8)
                        Text(stage.display).font(SR.Text.mono(14)).foregroundStyle(SR.ink).monospacedDigit()
                    }
                }
            }

            if !night.detail.isEmpty {
                Text(night.detail.joined(separator: " · "))
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(SR.cardPadding)
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("sleep-last-night")
    }

    @ViewBuilder private var figures: some View {
        figure("WHOOP", night.asleep, night.score.map { "\(Int($0.rounded()))% performance" })
        figure("WATCH", night.watch ?? "—", night.watch == nil ? "No reading" : "asleep")
    }

    private func figure(_ device: String, _ value: String, _ caption: String?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(device).font(SR.Text.mono()).tracking(1.2).foregroundStyle(SR.inkMuted)
            Text(value).font(SR.Text.figure(28)).foregroundStyle(value == "—" ? SR.inkGhost : SR.ink).lineLimit(1)
            if let caption { Text(caption).font(SR.Text.mono()).foregroundStyle(SR.inkMuted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var spoken: String {
        var parts = ["Last night, \(SleepFormat.day(night.date))", "WHOOP \(night.asleep) asleep"]
        if let score = night.score { parts.append("\(Int(score.rounded())) percent performance") }
        parts.append(night.watch.map { "Watch \($0) asleep" } ?? "Watch, no reading")
        parts += night.stages.map { "\($0.label) \($0.display)" }
        parts += night.detail
        return parts.joined(separator: ". ")
    }
}

/// Seven nights, both devices, a row each: the day, WHOOP's hours, the
/// Watch's, and WHOOP's sleep performance. Never a sum of the two.
struct SleepWeekCard: View {
    let nights: [HubDigest.Sleep.Night]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(nights.reversed().enumerated()), id: \.element.id) { index, night in
                if index > 0 { Rectangle().fill(SR.divider).frame(height: 1) }
                HStack(spacing: 10) {
                    Text(SleepFormat.day(night.date))
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(SleepFormat.hours(night.whoop))
                        .font(SR.Text.mono(14)).foregroundStyle(night.whoop == nil ? SR.inkGhost : SR.ink).monospacedDigit()
                    Text(SleepFormat.hours(night.watch))
                        .font(SR.Text.mono(14)).foregroundStyle(night.watch == nil ? SR.inkGhost : SR.inkSecondary).monospacedDigit()
                    Text(night.score.map { "\(Int($0.rounded()))%" } ?? "—")
                        .font(SR.Text.mono(14)).foregroundStyle(SR.inkMuted).monospacedDigit()
                        .frame(minWidth: 40, alignment: .trailing)
                }
                .padding(.horizontal, SR.cardPadding)
                .padding(.vertical, 10)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "\(SleepFormat.day(night.date)). WHOOP \(SleepFormat.hours(night.whoop)), Watch \(SleepFormat.hours(night.watch))"
                    + (night.score.map { ", \(Int($0.rounded())) percent performance" } ?? "")
                )
            }
        }
        .srGlassCard(.paper, radius: SR.Glass.innerRadius + 4)
        .accessibilityIdentifier("sleep-week")
    }
}
