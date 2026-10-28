import SwiftUI

// "Family now", drawn.
//
// SHARED with the widget extension (`SRAppleLive`, see watch.yml), beside
// the other family widgets' faces and for the same reason: drawn here so the
// app's gallery (Settings → Widget previews) can show them, which is how CI
// photographs a widget. The extension wraps each in its container
// background and tap URL.
//
// Prism: the widget is the Family tile on the Home Screen — the family hue
// as the ground, its type on top — and each person's circle wears their own
// colour, the one their pin wears on the map (`SRWidgetPalette.person`).

/// Who is home, out and on the move: a ring of circles round the count at
/// home (small), a row per person with where, how far, how fresh and their
/// battery (medium), and the counts on the Lock Screen.
struct FamilyNowWidgetView: View {
    let snapshot: FamilyNowSnapshot?
    let size: FamilyMessagesWidgetSize
    var now = Date()
    var palette: SRWidgetPalette = .prism

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Type on the family hue.
    private var on: Color { SRRGB.color(palette.family.onFill) }

    var body: some View {
        if let snapshot, !snapshot.people.isEmpty {
            switch size {
            case .small: small(snapshot)
            case .medium, .large: medium(snapshot)
            case .circular: circular(snapshot)
            case .rectangular: rectangular(snapshot)
            case .inline: Label(FamilyNow.counts(snapshot), systemImage: "house.fill")
            }
        } else {
            empty
        }
    }

    private var kicker: some View {
        Text("FAMILY NOW")
            .font(FamilyWidgetFont.label(10))
            .tracking(0.8)
            .opacity(0.85)
    }

    // MARK: - Home Screen

    /// Everyone round a ring, the count at home in the middle. Home is a
    /// full circle; out and on the move a circle with a mark; not seen
    /// lately or not sharing, faded.
    private func small(_ s: FamilyNowSnapshot) -> some View {
        let home = FamilyNow.count(s, .home)
        return VStack(alignment: .leading, spacing: 2) {
            kicker
            GeometryReader { geo in
                let side = min(geo.size.width, geo.size.height)
                let dot: CGFloat = s.people.count > 6 ? side * 0.22 : side * 0.26
                let radius = max(0, (side - dot) / 2)
                let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
                ZStack {
                    ForEach(Array(s.people.enumerated()), id: \.element.id) { index, person in
                        let angle = -Double.pi / 2 + Double(index) * 2 * .pi / Double(max(s.people.count, 1))
                        circle(person, size: dot, badge: true)
                            .position(x: centre.x + radius * CGFloat(cos(angle)), y: centre.y + radius * CGFloat(sin(angle)))
                    }
                    VStack(spacing: -2) {
                        Text("\(home)")
                            .font(FamilyWidgetFont.display(28))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("home")
                            .font(FamilyWidgetFont.label(10))
                            .opacity(0.85)
                    }
                    .frame(width: max(0, side - 2 * dot))
                    .position(centre)
                }
            }
        }
        .foregroundStyle(on)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryLabel(s))
    }

    private func medium(_ s: FamilyNowSnapshot) -> some View {
        let rows = typeSize >= .xxLarge ? 2 : typeSize >= .large ? 3 : 4
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                kicker
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(FamilyNow.count(s, .home))")
                        .font(FamilyWidgetFont.display(32))
                    Text("home")
                        .font(FamilyWidgetFont.label(12))
                        .opacity(0.85)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                if let away = awayLine(s) {
                    Text(away)
                        .font(FamilyWidgetFont.label(12))
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .frame(width: 82, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(s.people.prefix(rows)) { person in
                    row(person)
                }
                if s.people.count > rows {
                    Text("+\(s.people.count - rows) more")
                        .font(FamilyWidgetFont.label(10))
                        .opacity(0.8)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(on)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// "1 out · 1 moving", or nil with everyone home.
    private func awayLine(_ s: FamilyNowSnapshot) -> String? {
        let words: [(FamilyNowState, String)] = [(.out, "out"), (.moving, "moving")]
        let parts = words.compactMap { state, word -> String? in
            let n = FamilyNow.count(s, state)
            return n > 0 ? "\(n) \(word)" : nil
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// One person: their circle, name and where; how fresh and the battery.
    private func row(_ person: FamilyNowPerson) -> some View {
        HStack(alignment: .center, spacing: 7) {
            circle(person, size: 24, badge: false)
            VStack(alignment: .leading, spacing: 0) {
                Text(FamilyNow.who(person))
                    .font(FamilyWidgetFont.label(12))
                    .lineLimit(1)
                HStack(spacing: 3) {
                    Image(systemName: FamilyNow.symbol(person))
                        .font(FamilyWidgetFont.label(9))
                    Text(FamilyNow.line(person))
                        .font(FamilyWidgetFont.name(11))
                        .lineLimit(1)
                }
                .opacity(0.92)
            }
            Spacer(minLength: 2)
            VStack(alignment: .trailing, spacing: 0) {
                if let seen = FamilyNow.seen(person, now: now) {
                    Text(seen)
                        .font(FamilyWidgetFont.label(10))
                        .opacity(0.8)
                }
                if let pct = person.battery {
                    batteryChip(pct)
                }
            }
        }
        .opacity(FamilyNow.isStale(person, now: now) ? 0.7 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(FamilyNow.spoken(person, now: now))
    }

    /// "18%" beside its battery, filled in when it is low.
    private func batteryChip(_ pct: Int) -> some View {
        let low = FamilyNow.isLow(pct)
        return HStack(spacing: 2) {
            Image(systemName: FamilyNow.batterySymbol(pct))
                .font(FamilyWidgetFont.label(9))
            Text("\(pct)%")
                .font(FamilyWidgetFont.figure(10))
        }
        .padding(.horizontal, low ? 4 : 0)
        .background(Capsule().fill(on.opacity(low ? 0.22 : 0)))
        .lineLimit(1)
    }

    /// A person's circle: their initials on their colour, ringed in the
    /// widget's type colour so it reads on any family hue.
    private func circle(_ person: FamilyNowPerson, size: CGFloat, badge: Bool) -> some View {
        let colour = SRRGB.color(palette.person(person.hue))
        let faded = person.state == .off || person.state == .unseen
        return Text(person.initials)
            .font(FamilyWidgetFont.label(size * 0.38))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(colour.opacity(faded ? 0.45 : 1)))
            .overlay(Circle().stroke(on.opacity(person.state == .home ? 0.9 : 0.5), lineWidth: person.state == .home ? 1.5 : 1))
            .overlay(alignment: .bottomTrailing) {
                // Out or on the move: a small mark on the circle's edge.
                if badge, person.state == .out || person.state == .moving {
                    Image(systemName: FamilyNow.symbol(person))
                        .font(FamilyWidgetFont.label(size * 0.26))
                        .foregroundStyle(SRRGB.color(palette.family.base))
                        .frame(width: size * 0.42, height: size * 0.42)
                        .background(Circle().fill(on))
                        .offset(x: size * 0.08, y: size * 0.08)
                }
            }
            .accessibilityHidden(true)
    }

    // MARK: - Lock Screen

    private func circular(_ s: FamilyNowSnapshot) -> some View {
        let home = FamilyNow.count(s, .home)
        return Gauge(value: Double(home), in: 0...Double(max(s.people.count, 1))) {
            Image(systemName: "house.fill")
        } currentValueLabel: {
            Text("\(home)")
                .font(FamilyWidgetFont.figure(16))
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryLabel(s))
    }

    private func rectangular(_ s: FamilyNowSnapshot) -> some View {
        // The first somebody who is not home and not you: what a glance at
        // the Lock Screen is for.
        let away = s.people.first { !$0.isSelf && ($0.state == .moving || $0.state == .out) }
        return VStack(alignment: .leading, spacing: 1) {
            Text(FamilyNow.counts(s))
                .font(FamilyWidgetFont.label(13))
                .lineLimit(1)
            if let away {
                Text("\(away.name): \(FamilyNow.line(away))")
                    .font(FamilyWidgetFont.name(12))
                    .lineLimit(1)
            } else if let low = s.people.first(where: { FamilyNow.isLow($0.battery) && $0.state != .off }) {
                Text("\(FamilyNow.who(low)): battery \(low.battery ?? 0)%")
                    .font(FamilyWidgetFont.name(12))
                    .lineLimit(1)
            }
            Text("Family now").font(FamilyWidgetFont.label(11)).opacity(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summaryLabel(s))
    }

    // MARK: - Words for VoiceOver

    private func summaryLabel(_ s: FamilyNowSnapshot) -> String {
        (["Family now", FamilyNow.counts(s)] + s.people.map { FamilyNow.spoken($0, now: now) }).joined(separator: ". ")
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !size.lockScreen { kicker }
            Text(size == .inline ? "Family now" : "Open SR to see where everyone is.")
                .font(FamilyWidgetFont.name(13))
        }
        .foregroundStyle(size.lockScreen ? Color.primary : on)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
