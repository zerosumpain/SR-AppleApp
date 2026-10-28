import SwiftUI

// The Trips widget, drawn.
//
// SHARED with the widget extension (`SRAppleLive`, see watch.yml), beside the
// family widgets' faces and for the same reason: the app's gallery
// (Settings → Widget previews) draws them too.
//
// Prism: the Trips tile on the Home Screen — the trips hue as the ground, its
// type on top. Times are on the trip's own clock, as the plan and the Lock
// Screen card print them; the countdown to leaving is the system's own timer
// (`Text(timerInterval:)`), so it moves every second with no timeline entry.

/// On a trip day: the next stop, when to leave for it and how (small), and
/// the two after it (medium). Otherwise: the next trip and how long until it.
struct TripsWidgetView: View {
    let snapshot: TripsWidgetSnapshot?
    let size: FamilyMessagesWidgetSize
    var now = Date()
    var palette: SRWidgetPalette = .prism

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Type on the trips hue.
    private var on: Color { SRRGB.color(palette.trips.onFill) }

    var body: some View {
        let face = TripsWidget.face(snapshot, now: now)
        Group {
            if let snapshot {
                switch face {
                case .next(let stop, let after): next(snapshot, stop, after)
                case .dayDone: plain(snapshot, line: "Nothing more planned today", symbol: "moon.stars.fill")
                case .countdown(let days): countdown(snapshot, days)
                case .none: plain(snapshot, line: "Open SR for today's plan", symbol: "map.fill")
                }
            } else {
                empty
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(face))
    }

    private func kicker(_ text: String) -> some View {
        Text(text)
            .font(FamilyWidgetFont.label(10))
            .tracking(0.8)
            .opacity(0.85)
            .lineLimit(1)
    }

    // MARK: - A trip day

    @ViewBuilder
    private func next(_ s: TripsWidgetSnapshot, _ stop: TripsWidgetStop, _ after: [TripsWidgetStop]) -> some View {
        switch size {
        case .small: nextSmall(s, stop)
        case .medium, .large:
            HStack(alignment: .top, spacing: 14) {
                nextSmall(s, stop)
                    .frame(maxWidth: .infinity, alignment: .leading)
                laterStops(s, after)
                    .frame(width: 128, alignment: .leading)
            }
        case .circular:
            VStack(spacing: 0) {
                Image(systemName: TripsWidget.symbol(stop.legMode))
                    .font(FamilyWidgetFont.label(13))
                Text(TripsWidget.time(stop.leaveAt ?? stop.arriveAt, zone: s.timeZone))
                    .font(FamilyWidgetFont.figure(12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .rectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("Next: \(stop.title)")
                    .font(FamilyWidgetFont.label(13))
                    .lineLimit(1)
                Text([TripsWidget.leave(stop, now: now, zone: s.timeZone), TripsWidget.leg(stop)].compactMap { $0 }.joined(separator: " · "))
                    .font(FamilyWidgetFont.name(12))
                    .lineLimit(1)
                Text(s.title).font(FamilyWidgetFont.label(11)).opacity(0.7).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .inline:
            Label("\(stop.title) · \(TripsWidget.leave(stop, now: now, zone: s.timeZone))", systemImage: TripsWidget.symbol(stop.legMode))
        }
    }

    private func nextSmall(_ s: TripsWidgetSnapshot, _ stop: TripsWidgetStop) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            kicker(s.stopCount > 0 ? "NEXT · STOP \(stop.number) OF \(s.stopCount)" : "NEXT STOP")
            Text(stop.title)
                .font(FamilyWidgetFont.display(19))
                .lineLimit(typeSize > .large ? 1 : 2)
                .minimumScaleFactor(0.75)
            Spacer(minLength: 0)
            Text(TripsWidget.leave(stop, now: now, zone: s.timeZone))
                .font(FamilyWidgetFont.label(13))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            // The minutes to go, ticking, once leaving is within two hours.
            if let leave = stop.leaveAt, leave > now, leave.timeIntervalSince(now) <= 2 * 3600 {
                Text(timerInterval: now...leave, countsDown: true)
                    .font(FamilyWidgetFont.figure(20))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            if let leg = TripsWidget.leg(stop) {
                Label(leg, systemImage: TripsWidget.symbol(stop.legMode))
                    .font(FamilyWidgetFont.label(11))
                    .lineLimit(1)
                    .opacity(0.9)
            }
        }
        .foregroundStyle(on)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The stops after the next one, with when the plan gets there.
    private func laterStops(_ s: TripsWidgetSnapshot, _ after: [TripsWidgetStop]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            kicker(TripsWidget.dayLine(s)?.uppercased() ?? s.title.uppercased())
            if after.isEmpty {
                Text("The day's last stop.")
                    .font(FamilyWidgetFont.name(12))
                    .opacity(0.9)
            }
            ForEach(Array(after.prefix(typeSize >= .xLarge ? 1 : 2).enumerated()), id: \.offset) { _, stop in
                VStack(alignment: .leading, spacing: 0) {
                    Text(TripsWidget.time(stop.arriveAt, zone: s.timeZone))
                        .font(FamilyWidgetFont.figure(11))
                        .opacity(0.85)
                    Text(stop.title)
                        .font(FamilyWidgetFont.name(13))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(on)
    }

    // MARK: - The next trip

    @ViewBuilder
    private func countdown(_ s: TripsWidgetSnapshot, _ days: Int) -> some View {
        let words = TripsWidget.countdown(days)
        switch size {
        case .small, .medium, .large:
            VStack(alignment: .leading, spacing: 3) {
                kicker("NEXT TRIP")
                Text(s.title)
                    .font(FamilyWidgetFont.display(19))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                if days >= 2 {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(days)")
                            .font(FamilyWidgetFont.display(34))
                        Text("days to go")
                            .font(FamilyWidgetFont.label(12))
                            .opacity(0.85)
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                } else {
                    Text(words)
                        .font(FamilyWidgetFont.display(26))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Text([size == .small ? nil : s.destination, TripsWidget.range(s.startDate, s.endDate)].compactMap { $0 }.joined(separator: " · "))
                    .font(FamilyWidgetFont.name(12))
                    .lineLimit(1)
                    .opacity(0.9)
            }
            .foregroundStyle(on)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .circular:
            VStack(spacing: 0) {
                Text(days >= 1 ? "\(days)" : "0")
                    .font(FamilyWidgetFont.figure(17))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text(days == 1 ? "day" : "days")
                    .font(FamilyWidgetFont.label(9))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .rectangular:
            VStack(alignment: .leading, spacing: 1) {
                Text("\(s.title): \(words.lowercased())")
                    .font(FamilyWidgetFont.label(13))
                    .lineLimit(1)
                Text(TripsWidget.range(s.startDate, s.endDate))
                    .font(FamilyWidgetFont.name(12))
                    .lineLimit(1)
                Text("Next trip").font(FamilyWidgetFont.label(11)).opacity(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .inline:
            Label("\(s.title) · \(words)", systemImage: "airplane")
        }
    }

    // MARK: - Nothing next

    @ViewBuilder
    private func plain(_ s: TripsWidgetSnapshot, line: String, symbol: String) -> some View {
        if size.lockScreen {
            if size == .inline {
                Label(s.title, systemImage: symbol)
            } else if size == .circular {
                Image(systemName: symbol)
                    .font(FamilyWidgetFont.display(18))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    Text(s.title).font(FamilyWidgetFont.label(13)).lineLimit(1)
                    Text(line).font(FamilyWidgetFont.name(12)).lineLimit(1)
                    Text(TripsWidget.dayLine(s) ?? "Trips").font(FamilyWidgetFont.label(11)).opacity(0.7)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                kicker(TripsWidget.dayLine(s)?.uppercased() ?? "TRIPS")
                Text(s.title)
                    .font(FamilyWidgetFont.display(19))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                Spacer(minLength: 0)
                Label(line, systemImage: symbol)
                    .font(FamilyWidgetFont.name(12))
                    .lineLimit(2)
            }
            .foregroundStyle(on)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !size.lockScreen { kicker("TRIPS") }
            Text(size == .inline ? "Trips" : "No trip planned. Plan one in SR.")
                .font(FamilyWidgetFont.name(13))
        }
        .foregroundStyle(size.lockScreen ? Color.primary : on)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Words for VoiceOver

    private func spoken(_ face: TripsWidget.Face) -> String {
        guard let s = snapshot else { return "Trips. No trip planned." }
        switch face {
        case .next(let stop, let after):
            var parts = ["\(s.title)", "Next: \(stop.title)", TripsWidget.leave(stop, now: now, zone: s.timeZone)]
            if let leg = TripsWidget.leg(stop) { parts.append(leg) }
            if let then = after.first { parts.append("then \(then.title)") }
            return parts.joined(separator: ". ")
        case .dayDone: return "\(s.title). Nothing more planned today."
        case .countdown(let days): return "Next trip: \(s.title), \(TripsWidget.countdown(days).lowercased())."
        case .none: return "\(s.title). Open SR for today's plan."
        }
    }
}
