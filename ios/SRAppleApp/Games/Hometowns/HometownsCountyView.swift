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
                            .frame(height: 320)
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

    /// When the next Regional Day settles the county: a sun that climbs as
    /// the day comes, ticking once a minute while the sheet is open.
    @ViewBuilder
    private func clock(_ wire: HometownsWire) -> some View {
        if let c = wire.clock {
            TimelineView(.periodic(from: .now, by: 60)) { _ in
                HStack(alignment: .center, spacing: 14) {
                    sun(c)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(c.paused ? "The county is paused" : c.napping ? "The county is napping" : "Next Regional Day")
                            .font(SR.Text.title())
                            .foregroundStyle(SR.ink)
                        if !c.paused, !c.napping, let now = store.serverNow() {
                            Text(HometownsNumber.realTime(ms: c.nextRegionalDayAt - now).capitalizedFirst + " from now")
                                .font(SR.Text.bodyMedium(15))
                                .foregroundStyle(SR.accentInk)
                        }
                        Text("Season \(c.season.n) · day \(c.season.day + 1) · \(c.season.daysLeft) days left")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.inkMuted)
                    }
                    Spacer(minLength: 0)
                }
                .padding(SR.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .srGlassCard(.paper)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("hometowns-regional-day")
            }
        }
    }

    /// The share of the day gone (a Regional Day every 24 hours) as a ring round a sun.
    private func sun(_ c: HometownsClock) -> some View {
        let dayMs = 86_400_000.0
        let left = store.serverNow().map { max(0, min(dayMs, c.nextRegionalDayAt - $0)) } ?? dayMs
        let gone = c.paused || c.napping ? 0 : 1 - left / dayMs
        return ZStack {
            Circle().stroke(SR.line, lineWidth: 5)
            Circle()
                .trim(from: 0, to: CGFloat(gone))
                .stroke(Color(hex: 0xE0A030), style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: c.paused ? "pause.fill" : c.napping ? "moon.zzz.fill" : "sun.max.fill")
                .font(SR.Text.title(20))
                .foregroundStyle(c.paused || c.napping ? SR.inkMuted : Color(hex: 0xE0A030))
        }
        .frame(width: 56, height: 56)
        .accessibilityHidden(true)
    }

    private func towns(_ wire: HometownsWire) -> some View {
        VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Towns", trailing: "\(wire.towns.count) of 6")
            ForEach(wire.towns) { town in
                townCard(town, mine: town.seat == wire.me?.seat)
            }
        }
    }

    private func townCard(_ town: HometownsPublicTown, mine: Bool) -> some View {
        let tierName = store.copy.say("tier.\(town.tier)", store.level, or: HometownsCatalogue.tierName(town.tier))
        let growth = HometownsGrowth.of(population: town.pop, tier: town.tier)
        return HStack(alignment: .top, spacing: 12) {
            HometownsCritterBadge(animal: town.avatar, ground: HometownsColour.flag(town.flag), size: 48)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(town.name)
                        .font(SR.Text.title())
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if mine {
                        Text("YOURS")
                            .font(SR.Text.label(12))
                            .tracking(1)
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(SR.accent))
                    }
                }
                Text([town.mayor.isEmpty ? nil : "Mayor \(town.mayor)",
                      tierName,
                      "\(HometownsText.people(town.pop)) people",
                      town.inFortnight ? "founding" : nil,
                      town.holiday ? "on holiday" : nil].compactMap { $0 }.joined(separator: " · "))
                    .font(SR.Text.secondary())
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
                if growth.nextTier != nil {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(SR.line)
                            Capsule().fill(HometownsColour.flag(town.flag))
                                .frame(width: max(5, geo.size.width * CGFloat(growth.fraction)))
                        }
                    }
                    .frame(height: 5)
                    .padding(.top, 2)
                    .accessibilityHidden(true)
                }
                if !town.stars.isEmpty {
                    HometownsStars(halves: HometownsText.starHalves(town.stars.reduce(0, +) / Double(town.stars.count)))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(SR.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .overlay(alignment: .leading) {
            if mine { Capsule().fill(SR.accent).frame(width: 3).padding(.vertical, 18) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(townLabel(town, tierName: tierName, mine: mine))
        .accessibilityIdentifier("hometowns-town-card-\(town.seat)")
    }

    private func townLabel(_ town: HometownsPublicTown, tierName: String, mine: Bool) -> String {
        var parts = [town.name + (mine ? ", yours" : ""), tierName, "\(HometownsText.people(town.pop)) people"]
        if !town.mayor.isEmpty { parts.append("Mayor \(town.mayor)") }
        if !town.stars.isEmpty {
            let stars = HometownsText.starHalves(town.stars.reduce(0, +) / Double(town.stars.count))
            parts.append("\(HometownsNumber.oneDecimal(stars)) stars out of 5")
        }
        if town.inFortnight { parts.append("founding") }
        if town.holiday { parts.append("on holiday") }
        return parts.joined(separator: ", ")
    }
}

/// The county from above: a meadow, the County Roads in from six sites to
/// Kingsport's rooftops, each site drawn as its ground (river, coast, hills,
/// forest, flat), a town's flag on each one that has been founded — more
/// rooftops for a bigger tier — and the mayor's own ringed in the accent.
/// `selected` rings a free site in the founding screen. Static: a `Canvas`
/// redrawn only when the frame or the size changes.
struct HometownsRing: View {
    let wire: HometownsWire
    var selected: Int? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        Canvas { context, size in
            HometownsRing.draw(wire: wire, selected: selected, dark: dark, in: context, size: size)
        }
    }

    /// The radius of a site's disc for a ring of this size.
    static func siteRadius(_ size: CGSize) -> CGFloat { max(16, min(size.width, size.height) * 0.085) }

    /// How far the sites sit from Kingsport: a little in from the edge, and
    /// never so far that the lowest site's name or the top one's flag is cut
    /// off by the frame (the lobby card's ring is only 210 pt tall).
    static func ringRadius(_ size: CGSize) -> CGFloat {
        let fit = min(size.width, size.height) * 0.36
        let room = size.height / 2 - siteRadius(size) - 20
        return max(0, min(fit, room))
    }

    static func draw(wire: HometownsWire, selected: Int?, dark: Bool, in context: GraphicsContext, size: CGSize) {
        let centre = CGPoint(x: size.width / 2, y: size.height / 2)
        let radius = ringRadius(size)
        let siteR = siteRadius(size)
        // The meadow.
        let meadowR = min(size.width / 2, size.height / 2) * 0.98
        let meadow = CGRect(x: centre.x - meadowR * 1.08, y: centre.y - meadowR, width: meadowR * 2.16, height: meadowR * 2)
        context.fill(Path(ellipseIn: meadow), with: .radialGradient(
            Gradient(colors: dark ? [Color(hex: 0x3A4A30), Color(hex: 0x27321F)] : [Color(hex: 0xDDE8BE), Color(hex: 0xC2D69A)]),
            center: centre, startRadius: 0, endRadius: meadowR))
        // The County Roads in from each site.
        let roadColour = dark ? Color(hex: 0x6A6656) : Color(hex: 0xC9BC98)
        for k in 0..<6 {
            let p = Self.point(k, centre: centre, radius: radius)
            var road = Path()
            road.move(to: centre)
            road.addLine(to: p)
            context.stroke(road, with: .color(roadColour), style: StrokeStyle(lineWidth: 6, lineCap: .round))
            context.stroke(road, with: .color(Color.white.opacity(dark ? 0.25 : 0.6)), style: StrokeStyle(lineWidth: 1.2, dash: [4, 5]))
        }
        kingsport(context, centre: centre, unit: siteR * 0.5)
        context.draw(Text("Kingsport").font(SR.Text.label()).foregroundColor(SR.ink),
                     at: CGPoint(x: centre.x, y: centre.y + siteR * 1.25))
        // The sites, and the towns on them.
        for site in wire.county?.sites ?? [] {
            let p = Self.point(site.index, centre: centre, radius: radius)
            let disc = CGRect(x: p.x - siteR, y: p.y - siteR, width: siteR * 2, height: siteR * 2)
            var inDisc = context
            inDisc.clip(to: Path(ellipseIn: disc))
            inDisc.translateBy(x: disc.minX, y: disc.minY)
            HometownsSiteTile.draw(site.kind, in: inDisc, size: disc.size)
            if let owner = site.owner, wire.towns.indices.contains(owner) {
                let town = wire.towns[owner]
                let mine = town.seat == wire.me?.seat
                let flag = HometownsColour.flag(town.flag)
                let roofs = min(5, max(1, town.tier + 2))
                for r in 0..<roofs {
                    let angle = Double(r) / Double(roofs) * Double.pi * 2 + 0.6
                    let at = CGPoint(x: p.x + siteR * 0.42 * CGFloat(cos(angle)), y: p.y + siteR * 0.38 * CGFloat(sin(angle)))
                    house(context, at: at, unit: siteR * 0.28, roof: r % 2 == 0 ? Color(hex: 0xC0563C) : Color(hex: 0x8E5A3C))
                }
                context.stroke(Path(ellipseIn: disc), with: .color(mine ? SR.accent : flag), lineWidth: mine ? 4 : 3)
                pennant(context, at: CGPoint(x: p.x + siteR * 0.55, y: p.y - siteR * 0.6), height: siteR * 1.1, colour: flag)
                context.draw(Text(town.name).font(SR.Text.label()).foregroundColor(SR.ink),
                             at: CGPoint(x: p.x, y: p.y + siteR + 10))
            } else {
                context.fill(Path(ellipseIn: disc), with: .color(Color.white.opacity(dark ? 0.12 : 0.28)))
                let on = selected == site.index
                context.stroke(Path(ellipseIn: on ? disc.insetBy(dx: -4, dy: -4) : disc),
                               with: .color(on ? SR.accent : SR.inkGhost),
                               style: StrokeStyle(lineWidth: on ? 4 : 1.5, dash: on ? [] : [4, 4]))
                context.draw(Text(Self.siteName(site.kind)).font(SR.Text.label()).foregroundColor(on ? SR.accentInk : SR.inkMuted),
                             at: CGPoint(x: p.x, y: p.y + siteR + 10))
            }
        }
    }

    /// Kingsport: a ring of rooftops round its Green, with the clock tower.
    private static func kingsport(_ context: GraphicsContext, centre: CGPoint, unit: CGFloat) {
        let green = CGRect(x: centre.x - unit * 2.2, y: centre.y - unit * 1.7, width: unit * 4.4, height: unit * 3.4)
        context.fill(Path(ellipseIn: green), with: .color(Color(hex: 0x8DB866)))
        let roofs = [Color(hex: 0xC0563C), Color(hex: 0x8E5A3C), Color(hex: 0x3E6E8E), Color(hex: 0xA94A33)]
        for k in 0..<8 {
            let angle = Double(k) / 8 * Double.pi * 2
            let at = CGPoint(x: centre.x + unit * 1.6 * CGFloat(cos(angle)), y: centre.y + unit * 1.2 * CGFloat(sin(angle)))
            house(context, at: at, unit: unit * 0.75, roof: roofs[k % roofs.count])
        }
        // The clock tower.
        let tower = CGRect(x: centre.x - unit * 0.32, y: centre.y - unit * 1.3, width: unit * 0.64, height: unit * 1.5)
        context.fill(Path(tower), with: .color(Color(hex: 0xE9DCC6)))
        var spire = Path()
        spire.move(to: CGPoint(x: tower.minX - unit * 0.08, y: tower.minY))
        spire.addLine(to: CGPoint(x: tower.maxX + unit * 0.08, y: tower.minY))
        spire.addLine(to: CGPoint(x: tower.midX, y: tower.minY - unit * 0.7))
        spire.closeSubpath()
        context.fill(spire, with: .color(Color(hex: 0x3E6E8E)))
        context.fill(Path(ellipseIn: CGRect(x: tower.midX - unit * 0.18, y: tower.minY + unit * 0.2, width: unit * 0.36, height: unit * 0.36)),
                     with: .color(Color.white))
    }

    /// A little house from the front: a wall, a pitched roof and a door.
    private static func house(_ context: GraphicsContext, at p: CGPoint, unit: CGFloat, roof: Color) {
        let wall = CGRect(x: p.x - unit * 0.5, y: p.y - unit * 0.35, width: unit, height: unit * 0.7)
        context.fill(Path(wall), with: .color(Color(hex: 0xF1E6D2)))
        var top = Path()
        top.move(to: CGPoint(x: wall.minX - unit * 0.12, y: wall.minY))
        top.addLine(to: CGPoint(x: wall.maxX + unit * 0.12, y: wall.minY))
        top.addLine(to: CGPoint(x: wall.midX, y: wall.minY - unit * 0.55))
        top.closeSubpath()
        context.fill(top, with: .color(roof))
        context.fill(Path(CGRect(x: wall.midX - unit * 0.12, y: wall.maxY - unit * 0.38, width: unit * 0.24, height: unit * 0.38)),
                     with: .color(Color(hex: 0x6B4E33)))
    }

    /// A town's flag on a pole.
    private static func pennant(_ context: GraphicsContext, at base: CGPoint, height: CGFloat, colour: Color) {
        context.fill(Path(CGRect(x: base.x - 1, y: base.y - height, width: 2, height: height)), with: .color(Color(hex: 0x5A4A3A)))
        let flag = CGRect(x: base.x + 1, y: base.y - height, width: height * 0.62, height: height * 0.4)
        let shape = HometownsPennant().path(in: flag)
        context.fill(shape, with: .color(colour))
        context.stroke(shape, with: .color(Color.black.opacity(0.25)), lineWidth: 1)
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
