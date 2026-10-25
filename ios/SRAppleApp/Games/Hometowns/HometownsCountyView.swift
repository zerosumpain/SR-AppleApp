import SwiftUI

/// The County (§9.10), as M1 has it: a solo county is a real game, so this is
/// the ring of six sites around Kingsport with the towns on them, drawn in a
/// `Canvas` (the Homestead board precedent), and each town's public card.
/// Links, the Regional Day replay, visits and the county's panels arrive with
/// the multiplayer milestone (M2); a public card here never shows another
/// town's money, which the wire does not carry.
struct HometownsCountyView: View {
    @ObservedObject var store: HometownsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SR.sectionGap) {
                    if let wire = store.wire {
                        HometownsRing(wire: wire)
                            .frame(height: 300)
                            .padding(.vertical, 4)
                            .srGlassCard(.paper)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(ringLabel(wire))
                            .accessibilityIdentifier("hometowns-ring")
                        clock(wire)
                        towns(wire)
                    }
                }
                .padding(.horizontal, SR.gutter)
                .padding(.vertical, 12)
            }
            .srGround(.warm)
            .navigationTitle(store.wire?.county?.name ?? "The county")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .accessibilityIdentifier("hometowns-county")
    }

    private func ringLabel(_ wire: HometownsWire) -> String {
        let names = wire.towns.map(\.name)
        let free = wire.freeSites.count
        return "Kingsport in the middle, with \(names.isEmpty ? "no towns yet" : GameNames.list(names)) around it, and \(free) free site\(free == 1 ? "" : "s")."
    }

    /// When the next Regional Day settles the county.
    @ViewBuilder
    private func clock(_ wire: HometownsWire) -> some View {
        if let c = wire.clock {
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                VStack(alignment: .leading, spacing: 4) {
                    Text(c.paused ? "The county is paused" : c.napping ? "The county is napping" : "Next Regional Day")
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                    if !c.paused, !c.napping, let now = store.serverNow() {
                        Text(HometownsNumber.realTime(ms: c.nextRegionalDayAt - now).capitalizedFirst + " from now")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkSecondary)
                    }
                    Text("Season \(c.season.n) · day \(c.season.day + 1) · \(c.season.daysLeft) days left")
                        .font(SR.Text.mono())
                        .foregroundStyle(SR.inkMuted)
                }
                .padding(SR.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .srGlassCard(.paper)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("hometowns-regional-day")
            }
        }
    }

    private func towns(_ wire: HometownsWire) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Towns", trailing: "\(wire.towns.count) of 6")
            ForEach(wire.towns) { town in
                HStack(spacing: 12) {
                    Circle()
                        .fill(HometownsColour.flag(town.flag))
                        .overlay(Circle().stroke(SR.line, lineWidth: 1))
                        .frame(width: 18, height: 18)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(town.name + (town.seat == wire.me?.seat ? " (yours)" : ""))
                            .font(SR.Text.title())
                            .foregroundStyle(SR.ink)
                        Text([town.mayor.isEmpty ? nil : "Mayor \(town.mayor)",
                              store.copy.say("tier.\(town.tier)", store.level, or: HometownsCatalogue.tierName(town.tier)),
                              "\(HometownsText.people(town.pop)) people",
                              town.inFortnight ? "founding" : nil,
                              town.holiday ? "on holiday" : nil].compactMap { $0 }.joined(separator: " · "))
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 8)
                    if !town.stars.isEmpty {
                        HometownsStars(halves: HometownsText.starHalves(town.stars.reduce(0, +) / Double(town.stars.count)))
                    }
                }
                .padding(SR.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .srGlassCard(.paper)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("hometowns-town-card-\(town.seat)")
            }
        }
    }
}

/// Kingsport and its Green in the middle, six sites round it, a town on each
/// one that has been founded — bigger for a bigger tier.
struct HometownsRing: View {
    let wire: HometownsWire

    var body: some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) * 0.36
            // The County Roads in from each site.
            for k in 0..<6 {
                let p = Self.point(k, centre: centre, radius: radius)
                var road = Path()
                road.move(to: centre)
                road.addLine(to: p)
                context.stroke(road, with: .color(SR.line), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [6, 6]))
            }
            // Kingsport.
            let k = CGRect(x: centre.x - 30, y: centre.y - 30, width: 60, height: 60)
            context.fill(Path(ellipseIn: k), with: .color(SR.good.opacity(0.35)))
            context.fill(Path(ellipseIn: k.insetBy(dx: 14, dy: 14)), with: .color(SR.ink))
            context.draw(Text("Kingsport").font(SR.Text.label()).foregroundColor(SR.ink),
                         at: CGPoint(x: centre.x, y: centre.y + 42))
            // The sites, and the towns on them.
            for site in wire.county?.sites ?? [] {
                let p = Self.point(site.index, centre: centre, radius: radius)
                if let owner = site.owner, wire.towns.indices.contains(owner) {
                    let town = wire.towns[owner]
                    let r = 12 + CGFloat(min(4, max(0, town.tier))) * 4
                    let disc = CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)
                    context.fill(Path(ellipseIn: disc), with: .color(HometownsColour.flag(town.flag)))
                    context.stroke(Path(ellipseIn: disc), with: .color(town.seat == wire.me?.seat ? SR.accent : SR.ink), lineWidth: 2)
                    context.draw(Text(town.name).font(SR.Text.label()).foregroundColor(SR.ink),
                                 at: CGPoint(x: p.x, y: p.y + r + 10))
                } else {
                    let disc = CGRect(x: p.x - 10, y: p.y - 10, width: 20, height: 20)
                    context.stroke(Path(ellipseIn: disc), with: .color(SR.inkGhost), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    context.draw(Text(Self.siteName(site.kind)).font(SR.Text.label()).foregroundColor(SR.inkMuted),
                                 at: CGPoint(x: p.x, y: p.y + 22))
                }
            }
        }
    }

    /// Site k on the ring, clockwise from the top.
    static func point(_ k: Int, centre: CGPoint, radius: CGFloat) -> CGPoint {
        let angle = -Double.pi / 2 + Double(k) * Double.pi / 3
        return CGPoint(x: centre.x + radius * CGFloat(cos(angle)), y: centre.y + radius * CGFloat(sin(angle)))
    }

    static func siteName(_ kind: String) -> String {
        switch kind {
        case "river": return "River"
        case "coast": return "Coast"
        case "hills": return "Hills"
        case "forest": return "Forest"
        default: return "Flatland"
        }
    }
}

private extension String {
    /// "about 2 hours" → "About 2 hours".
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
