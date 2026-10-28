import SwiftUI

// The "Health today" widget, drawn.
//
// SHARED with the widget extension (`SRAppleLive`, see watch.yml), beside the
// family widgets' faces and for the same reason: the app's gallery
// (Settings → Widget previews) draws them too.
//
// Prism: the Health tile on the Home Screen — the health hue as the ground,
// its type on top. The rings nest the way the Watch draws them, Move
// outermost, in the type colour at three strengths: on a coloured ground the
// Watch's own red, green and blue would fight it.

/// Today's rings with readiness (the owner) or Move in the middle, and the
/// steps (small); each ring's figures beside them (medium).
struct HealthWidgetView: View {
    let snapshot: HealthWidgetSnapshot?
    let size: FamilyMessagesWidgetSize
    var now = Date()
    var palette: SRWidgetPalette = .prism

    @Environment(\.dynamicTypeSize) private var typeSize

    /// Type on the health hue.
    private var on: Color { SRRGB.color(palette.healthHue.onFill) }

    var body: some View {
        if let shown = HealthWidget.today(snapshot, now: now) {
            let carried = snapshot.map { HealthWidget.isCarriedOver($0, now: now) } ?? false
            switch size {
            case .small: small(shown, carried: carried)
            case .medium, .large: medium(shown, carried: carried)
            case .circular: circular(shown)
            case .rectangular: rectangular(shown, carried: carried)
            case .inline: Label(inline(shown), systemImage: "figure.walk")
            }
        } else {
            empty
        }
    }

    private var kicker: some View {
        Text("TODAY")
            .font(FamilyWidgetFont.label(10))
            .tracking(0.8)
            .opacity(0.85)
    }

    // MARK: - Home Screen

    private func small(_ s: HealthWidgetSnapshot, carried: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            kicker
            rings(s)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            stepsLine(s, carried: carried)
        }
        .foregroundStyle(on)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(s, carried: carried))
    }

    private func medium(_ s: HealthWidgetSnapshot, carried: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                kicker
                rings(s)
            }
            .frame(width: 118)
            VStack(alignment: .leading, spacing: typeSize >= .xLarge ? 2 : 5) {
                if let readiness = s.readiness {
                    figureRow(label: "Readiness", value: "\(readiness)", detail: s.readinessLabel)
                }
                ForEach(s.rings.prefix(typeSize >= .xLarge ? 2 : 3)) { ring in
                    figureRow(label: ring.label, value: "\(HealthWidget.percent(ring))%", detail: HealthWidget.figure(ring))
                }
                if s.rings.isEmpty && s.readiness == nil {
                    Text("No rings yet. Apple Health shares them with SR in Settings.")
                        .font(FamilyWidgetFont.name(12))
                        .lineLimit(3)
                }
                Spacer(minLength: 0)
                stepsLine(s, carried: carried)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(on)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(s, carried: carried))
    }

    private func figureRow(label: String, value: String, detail: String?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(label)
                .font(FamilyWidgetFont.label(11))
                .opacity(0.85)
                .lineLimit(1)
            Spacer(minLength: 2)
            Text(value)
                .font(FamilyWidgetFont.figure(13))
            if let detail, typeSize < .xLarge {
                Text(detail)
                    .font(FamilyWidgetFont.name(10))
                    .opacity(0.8)
                    .lineLimit(1)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }

    /// "9,120 steps", or — on a new day the app has not seen yet — a nudge.
    @ViewBuilder
    private func stepsLine(_ s: HealthWidgetSnapshot, carried: Bool) -> some View {
        if carried {
            Text("New day. Open SR to update.")
                .font(FamilyWidgetFont.name(11))
                .lineLimit(2)
                .opacity(0.9)
        } else if let steps = s.steps {
            Label("\(HealthWidget.steps(steps)) steps", systemImage: "shoeprints.fill")
                .font(FamilyWidgetFont.label(12))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    /// The nested rings, outermost first, with the centre's figure.
    private func rings(_ s: HealthWidgetSnapshot) -> some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let line = max(4, side * 0.1)
            let centre = HealthWidget.centre(s)
            ZStack {
                ForEach(Array(s.rings.enumerated()), id: \.element.id) { index, ring in
                    let strength = [1.0, 0.78, 0.56][min(index, 2)]
                    ZStack {
                        Circle().stroke(on.opacity(0.2), lineWidth: line)
                        Circle()
                            .trim(from: 0, to: min(max(ring.fraction, 0), 1))
                            .stroke(on.opacity(strength), style: StrokeStyle(lineWidth: line, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .padding(CGFloat(index) * (line + 1.5) + line / 2)
                }
                VStack(spacing: -2) {
                    Text(centre.figure)
                        .font(FamilyWidgetFont.figure(side * 0.2))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text(centre.word)
                        .font(FamilyWidgetFont.label(9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .opacity(0.85)
                }
                .frame(width: max(0, side - 2 * CGFloat(max(s.rings.count, 1)) * (line + 1.5) - 4))
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .accessibilityHidden(true)
    }

    // MARK: - Lock Screen

    @ViewBuilder
    private func circular(_ s: HealthWidgetSnapshot) -> some View {
        if let move = s.rings.first(where: { $0.key == "move" }) {
            Gauge(value: min(max(move.fraction, 0), 1)) {
                Image(systemName: "flame.fill")
            } currentValueLabel: {
                Text("\(HealthWidget.percent(move))")
                    .font(FamilyWidgetFont.figure(15))
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityLabel("Move \(HealthWidget.percent(move)) percent")
        } else {
            VStack(spacing: 0) {
                Image(systemName: "shoeprints.fill")
                    .font(FamilyWidgetFont.label(12))
                Text(s.steps.map(HealthWidget.compact) ?? "—")
                    .font(FamilyWidgetFont.figure(14))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(s.steps.map { "\(HealthWidget.steps($0)) steps" } ?? "No steps yet")
        }
    }

    private func rectangular(_ s: HealthWidgetSnapshot, carried: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(HealthWidget.ringsLine(s) ?? "No rings yet")
                .font(FamilyWidgetFont.label(13))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(carried ? "New day · open SR" : [s.steps.map { "\(HealthWidget.steps($0)) steps" },
                                                  s.readiness.map { "Readiness \($0)" }].compactMap { $0 }.joined(separator: " · "))
                .font(FamilyWidgetFont.name(12))
                .lineLimit(1)
            Text("Health today").font(FamilyWidgetFont.label(11)).opacity(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken(s, carried: carried))
    }

    private func inline(_ s: HealthWidgetSnapshot) -> String {
        var parts: [String] = []
        if let steps = s.steps { parts.append("\(HealthWidget.steps(steps)) steps") }
        if let move = s.rings.first(where: { $0.key == "move" }) { parts.append("Move \(HealthWidget.percent(move))%") }
        return parts.isEmpty ? "Health today" : parts.joined(separator: " · ")
    }

    private func spoken(_ s: HealthWidgetSnapshot, carried: Bool) -> String {
        "Health today. " + (carried ? "A new day: open SR to update." : HealthWidget.spoken(s))
    }

    private var empty: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !size.lockScreen { kicker }
            Text(size == .inline ? "Health today" : "Open SR to see today's rings.")
                .font(FamilyWidgetFont.name(13))
        }
        .foregroundStyle(size.lockScreen ? Color.primary : on)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
