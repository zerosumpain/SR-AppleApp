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
