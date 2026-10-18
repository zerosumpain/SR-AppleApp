import SwiftUI
import CoreLocation

// The family, drawn rather than mapped.
//
// A map answers "where exactly", and the Family tab still has one. What a
// glance at a phone wants is a different question — who is home, who is far,
// who is on their way — and a map answers it badly: two people at home are one
// pin, somebody in the next town is off the edge, and nothing says "far" except
// the zoom level.
//
// So two pictures, both built from data the household view already carries:
//
// - **The Orbit.** Home is the sun. Each person is a planet: how far they are
//   is how far out they sit (on a log scale, so the school run and the trip to
//   London both read), and the direction they are in is the direction from
//   home — north is up. Everyone at home circles the sun on the innermost
//   ring. A polar distance chart of the kind data-journalism desks use for
//   "how far from home", with the people as the data.
// - **The Ribbons.** Each person's day as a ridgeline — the Joy Division plot,
//   "Unknown Pleasures" — with time across and distance from home as height.
//   A school run is a hill, a day out is a mountain, a day in is a flat line.
//   Gaps in the trail stay gaps: joining them draws a journey nobody took.
//
// The maths is pure and lives in `FamilyOrbitMath` / `FamilyRibbonMath`, so
// every rule is a unit test rather than something only a screenshot shows.

// MARK: - Geometry

struct GeoPoint: Equatable {
    let lat: Double
    let lon: Double
}

enum FamilyOrbitMath {
    /// Great-circle distance, kilometres.
    static func distanceKm(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let r = 6371.0
        let dLat = (b.lat - a.lat) * .pi / 180
        let dLon = (b.lon - a.lon) * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.lat * .pi / 180) * cos(b.lat * .pi / 180) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }

    /// The compass bearing from `a` to `b`, radians: 0 is north, clockwise.
    static func bearing(from a: GeoPoint, to b: GeoPoint) -> Double {
        let φ1 = a.lat * .pi / 180, φ2 = b.lat * .pi / 180
        let Δλ = (b.lon - a.lon) * .pi / 180
        let y = sin(Δλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(Δλ)
        let θ = atan2(y, x)
        return θ < 0 ? θ + 2 * .pi : θ
    }

    /// "north-east", for VoiceOver. Eight points: finer than that is noise
    /// at the accuracy a family phone reports.
    static func compass(_ bearing: Double) -> String {
        let names = ["north", "north-east", "east", "south-east", "south", "south-west", "west", "north-west"]
        let index = Int(((bearing / (2 * .pi)) * 8).rounded()) % 8
        return names[index]
    }

    /// Where home is. PURE.
    ///
    /// A watched place called home is the best answer: somebody set it. Then
    /// where the people the site says are home are standing (the median, so
    /// one wild fix cannot drag it down the road). Nil when neither is known,
    /// and the Orbit centres on you instead.
    static func home(people: [FamilyPerson], watch: [WatchedPlace]?) -> GeoPoint? {
        if let place = watch?.first(where: { $0.label.lowercased().contains("home") }) {
            return GeoPoint(lat: place.lat, lon: place.lon)
        }
        let fixes = people.filter { $0.status == "home" }.compactMap(\.position)
        guard !fixes.isEmpty else { return nil }
        return GeoPoint(lat: median(fixes.map(\.lat)), lon: median(fixes.map(\.lon)))
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }

    /// The share of the radius the sun and the at-home ring take.
    static let inner = 0.26
    /// Distances under this are home, whatever the site's status says: a
    /// fix in the garden is not a trip.
    static let homeKm = 0.15
    /// The log scale's knee. Below it the scale is close to linear.
    static let knee = 0.3

    /// How far out a distance sits, 0 (the sun) to 1 (the edge). PURE.
    static func radius(km: Double, maxKm: Double) -> Double {
        guard maxKm > 0 else { return inner }
        let t = log1p(max(0, km) / knee) / log1p(maxKm / knee)
        return inner + (1 - inner) * min(1, t)
    }

    /// The outermost ring: the next round number past the farthest person,
    /// never under 5 km, so a quiet day at home is not drawn at a scale
    /// where the corner shop is the edge of the world.
    static func outerKm(farthest: Double) -> Double {
        let steps: [Double] = [5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 20000]
        return steps.first { $0 >= farthest * 1.15 } ?? 20000
    }

    /// Up to three labelled rings inside the outer one.
    static func rings(outer: Double) -> [Double] {
        let marks: [Double] = [1, 2, 5, 10, 25, 50, 100, 250, 500, 1000, 2500, 5000]
        let inside = marks.filter { $0 < outer }
        return Array(inside.suffix(2)) + [outer]
    }

    struct Body: Equatable {
        let subject: String
        let km: Double
        let bearing: Double
        let atHome: Bool
    }

    struct Placed: Equatable {
        let subject: String
        /// Unit coordinates, -1…1, y DOWN (screen space): north is -y.
        var x: Double
        var y: Double
        let atHome: Bool
    }

    /// Where each body is drawn. PURE.
    ///
    /// At home: evenly round the inner ring, so three people at home are
    /// three planets and not one pin. Everyone else at their distance and
    /// bearing, then nudged apart until no two overlap — two people at the
    /// same school stay side by side, a hair apart, rather than one on top
    /// of the other.
    static func place(_ bodies: [Body], outer: Double, separation: Double = 0.2) -> [Placed] {
        let home = bodies.filter(\.atHome)
        var out: [Placed] = home.enumerated().map { index, body in
            let angle = -Double.pi / 2 + Double(index) * 2 * .pi / Double(max(home.count, 1)) + (home.count == 1 ? .pi / 5 : 0)
            let r = inner * 0.72
            return Placed(subject: body.subject, x: r * cos(angle), y: r * sin(angle), atHome: true)
        }
        var away: [Placed] = bodies.filter { !$0.atHome }.map { body in
            let r = radius(km: body.km, maxKm: outer)
            // Bearing 0 is north, which is up the screen: x = sin, y = -cos.
            return Placed(subject: body.subject, x: r * sin(body.bearing), y: -r * cos(body.bearing), atHome: false)
        }
        for _ in 0..<8 {
            var moved = false
            for i in away.indices {
                for j in away.indices where j > i {
                    let dx = away[j].x - away[i].x, dy = away[j].y - away[i].y
                    let d = max(sqrt(dx * dx + dy * dy), 0.0001)
                    guard d < separation else { continue }
                    let push = (separation - d) / 2
                    let ux = d < 0.001 ? 1 : dx / d, uy = d < 0.001 ? 0 : dy / d
                    away[i].x -= ux * push; away[i].y -= uy * push
                    away[j].x += ux * push; away[j].y += uy * push
                    moved = true
                }
            }
            for i in away.indices {
                let len = sqrt(away[i].x * away[i].x + away[i].y * away[i].y)
                if len > 1 { away[i].x /= len; away[i].y /= len }
            }
            if !moved { break }
        }
        out.append(contentsOf: away)
        return out
    }

    /// A point of a trail in the same unit space as `place`.
    static func project(_ point: GeoPoint, home: GeoPoint, outer: Double) -> CGPoint {
        let km = distanceKm(home, point)
        let r = km < homeKm ? inner * 0.72 : radius(km: km, maxKm: outer)
        let b = bearing(from: home, to: point)
        return CGPoint(x: r * sin(b), y: -r * cos(b))
    }
}

/// The Orbit's input, worked out once from a household view.
struct FamilyOrbitModel: Equatable {
    struct Person: Equatable, Identifiable {
        let subject: String
        let name: String
        let initials: String
        let isSelf: Bool
        let km: Double
        let bearing: Double
        let atHome: Bool
        let battery: Int?
        let moving: FamilyPerson.Moving?
        let stale: Bool
        let place: String?
        /// The last twenty minutes of today's trail, in unit space — the tail
        /// behind somebody on the move. Empty for everyone else.
        let tail: [CGPoint]

        var id: String { subject }
    }

    let people: [Person]
    /// Sharing, but nowhere to put them, or not sharing at all.
    let missing: [String]
    let outer: Double
    /// Whether the centre is home, or — no home known — you.
    let centredOnHome: Bool

    static func make(view: HouseholdView, watch: [WatchedPlace]?, now: Date = Date()) -> FamilyOrbitModel? {
        let initials = view.initials
        let selfFix = view.people.first(where: \.isSelf)?.position.map { GeoPoint(lat: $0.lat, lon: $0.lon) }
        let homeFix = FamilyOrbitMath.home(people: view.people, watch: watch)
        guard let centre = homeFix ?? selfFix ?? view.placed.first?.position.map({ GeoPoint(lat: $0.lat, lon: $0.lon) }) else {
            return nil
        }
        let placed = view.people.filter { $0.position != nil && $0.status != "off" }
        let measured = placed.map { person -> (FamilyPerson, Double, Double) in
            let p = GeoPoint(lat: person.position!.lat, lon: person.position!.lon)
            return (person, FamilyOrbitMath.distanceKm(centre, p), FamilyOrbitMath.bearing(from: centre, to: p))
        }
        let outer = FamilyOrbitMath.outerKm(farthest: measured.map { $0.1 }.max() ?? 0)
        let cutoff = now.timeIntervalSince1970 - 20 * 60
        let people = measured.map { entry -> Person in
            let (person, km, bearing) = entry
            let atHome = homeFix != nil && (person.status == "home" || km < FamilyOrbitMath.homeKm)
            let tail: [CGPoint] = person.moving == nil ? [] : (person.today?.trail ?? [])
                .filter { $0.count >= 3 && $0[2] >= cutoff }
                .map { FamilyOrbitMath.project(GeoPoint(lat: $0[0], lon: $0[1]), home: centre, outer: outer) }
            return Person(
                subject: person.subject, name: person.name,
                initials: initials[person.subject] ?? person.initial,
                isSelf: person.isSelf, km: km, bearing: bearing, atHome: atHome,
                battery: person.batteryPct, moving: person.moving,
                stale: person.freshness(now: now) == .stale,
                place: person.placeName, tail: tail
            )
        }
        let missing = view.people.filter { $0.position == nil || $0.status == "off" }.map(\.name)
        return FamilyOrbitModel(people: people, missing: missing, outer: outer, centredOnHome: homeFix != nil)
    }

    /// "Sam, 2.4 km north-east of home, walking, battery 54%".
    func spoken(_ person: Person) -> String {
        var parts = [person.isSelf ? "You" : person.name]
        if person.atHome {
            parts.append("at home")
        } else {
            let anchor = centredOnHome ? "home" : "you"
            parts.append("\(FamilyOrbitMath.formatKm(person.km)) \(FamilyOrbitMath.compass(person.bearing)) of \(anchor)")
            if let place = person.place, place != "Home" { parts.append("near \(place)") }
        }
        if let moving = person.moving { parts.append(moving.verb) }
        if let battery = person.battery { parts.append("battery \(battery)%") }
        if person.stale { parts.append("not seen lately") }
        return parts.joined(separator: ", ")
    }
}

extension FamilyOrbitMath {
    /// "800 m", "2.4 km", "38 km".
    static func formatKm(_ km: Double) -> String {
        if km < 1 { return "\(Int((km * 1000 / 50).rounded() * 50)) m" }
        return km < 10 ? String(format: "%.1f km", km) : "\(Int(km.rounded())) km"
    }

    /// "5 km", "250 km" — a ring's label.
    static func ringLabel(_ km: Double) -> String {
        km >= 1000 ? "\(Int(km / 1000))k km" : "\(Int(km)) km"
    }
}

// MARK: - The Orbit

/// Home as the sun, the family as planets. See the note at the top of the file.
///
/// The rings and the tails are one `Canvas` (drawn once per change, no
/// layers), the people are views — each one a VoiceOver element and a tap
/// target. Nothing moves while idle: the one animation is the halo round
/// somebody on the move, and only while `live`.
struct FamilyOrbitView: View {
    let model: FamilyOrbitModel
    let colours: [String: Color]
    /// On screen and the app in front: the moving halo may pulse.
    var live: Bool = false
    /// A planet tapped; nil leaves the whole view to the caller's tap.
    var openPerson: ((String) -> Void)? = nil
    @ScaledMetric(relativeTo: .body) private var planet: CGFloat = 34
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2 - planet * 0.6
            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let placed = Dictionary(FamilyOrbitMath.place(
                model.people.map { .init(subject: $0.subject, km: $0.km, bearing: $0.bearing, atHome: $0.atHome) },
                outer: model.outer,
                separation: Double(planet * 1.1 / max(radius, 1))
            ).map { ($0.subject, $0) }, uniquingKeysWith: { first, _ in first })

            ZStack {
                rings(centre: centre, radius: radius)
                sun.position(centre)
                ForEach(model.people) { person in
                    if let spot = placed[person.subject] {
                        planetView(person)
                            .position(x: centre.x + spot.x * radius, y: centre.y + spot.y * radius)
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("family-orbit")
    }

    /// The rings, their labels, the compass tick and every tail.
    private func rings(centre: CGPoint, radius: CGFloat) -> some View {
        let outer = model.outer
        let marks = FamilyOrbitMath.rings(outer: outer)
        let lineColour = SR.ink.opacity(scheme == .dark ? 0.16 : 0.10)
        return Canvas { context, _ in
            // The faint disc the planets sit on.
            let disc = Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius, width: radius * 2, height: radius * 2))
            context.fill(disc, with: .radialGradient(
                Gradient(colors: [SR.Hue.family.glow.opacity(0.10), SR.Hue.trips.glow.opacity(0.06), .clear]),
                center: centre, startRadius: 0, endRadius: radius
            ))
            for km in marks {
                let r = radius * FamilyOrbitMath.radius(km: km, maxKm: outer)
                let ring = Path(ellipseIn: CGRect(x: centre.x - r, y: centre.y - r, width: r * 2, height: r * 2))
                context.stroke(ring, with: .color(lineColour), style: StrokeStyle(lineWidth: 1, dash: km == outer ? [] : [3, 4]))
                let label = Text(FamilyOrbitMath.ringLabel(km))
                    .font(SR.Text.label(10))
                    .foregroundStyle(SR.inkMuted)
                context.draw(label, at: CGPoint(x: centre.x + r * 0.707 + 4, y: centre.y + r * 0.707 + 2), anchor: .topLeading)
            }
            let homeRing = radius * FamilyOrbitMath.inner * 0.72
            context.stroke(Path(ellipseIn: CGRect(x: centre.x - homeRing, y: centre.y - homeRing, width: homeRing * 2, height: homeRing * 2)),
                           with: .color(SR.Hue.family.base.opacity(0.25)), lineWidth: 1.5)
            // North.
            let n = Text("N").font(SR.Text.label(10)).foregroundStyle(SR.inkMuted)
            context.draw(n, at: CGPoint(x: centre.x, y: centre.y - radius - 2), anchor: .bottom)
            // Tails: the last twenty minutes behind anybody on the move,
            // fading towards where they were.
            for person in model.people where person.tail.count > 1 {
                let colour = colours[person.subject] ?? SR.accent
                var path = Path()
                for (index, point) in person.tail.enumerated() {
                    let p = CGPoint(x: centre.x + point.x * radius, y: centre.y + point.y * radius)
                    if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
                }
                context.stroke(path, with: .linearGradient(
                    Gradient(colors: [colour.opacity(0), colour.opacity(0.85)]),
                    startPoint: CGPoint(x: centre.x + person.tail[0].x * radius, y: centre.y + person.tail[0].y * radius),
                    endPoint: CGPoint(x: centre.x + person.tail.last!.x * radius, y: centre.y + person.tail.last!.y * radius)
                ), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }

    private var sun: some View {
        ZStack {
            Circle()
                .fill(SR.Hue.family.gradient)
                .frame(width: planet * 1.25, height: planet * 1.25)
                .shadow(color: SR.Hue.family.glow.opacity(0.55), radius: 14)
            Image(systemName: model.centredOnHome ? "house.fill" : "location.fill")
                .font(.system(size: planet * 0.45, weight: .bold))
                .foregroundStyle(.white)
        }
        .accessibilityLabel(model.centredOnHome ? "Home" : "You")
    }

    @ViewBuilder
    private func planetView(_ person: FamilyOrbitModel.Person) -> some View {
        let colour = colours[person.subject] ?? SR.accent
        let disc = OrbitPlanet(person: person, colour: colour, size: planet, live: live)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.spoken(person))
            .accessibilityIdentifier("orbit-\(person.subject)")
        if let openPerson {
            Button { SRHaptic.tap(); openPerson(person.subject) } label: { disc }
                .buttonStyle(SRPressStyle())
                .accessibilityAddTraits(.isButton)
        } else {
            disc
        }
    }
}

/// One person: their colour, their initials, their battery as a ring round
/// the edge, and — on the move — a halo and the way they are going.
struct OrbitPlanet: View {
    let person: FamilyOrbitModel.Person
    let colour: Color
    let size: CGFloat
    var live: Bool = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if person.moving != nil {
                halo
            }
            Circle()
                .fill(LinearGradient(colors: [colour.opacity(0.85), colour], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: person.isSelf ? 3 : 2))
                .shadow(color: colour.opacity(0.45), radius: 6, y: 2)
            Text(person.initials)
                .font(SR.Text.title(size * 0.38))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let battery = person.battery {
                Circle()
                    .trim(from: 0, to: CGFloat(max(0.04, min(1, Double(battery) / 100))))
                    .stroke(batteryColour(battery), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(-4.5)
            }
            if let moving = person.moving {
                Image(systemName: moving.symbol)
                    .font(.system(size: size * 0.26, weight: .bold))
                    .foregroundStyle(colour)
                    .frame(width: size * 0.44, height: size * 0.44)
                    .background(Circle().fill(.white))
                    .offset(x: size * 0.42, y: size * 0.36)
            }
        }
        .frame(width: size, height: size)
        .opacity(person.stale ? 0.55 : 1)
        .saturation(person.stale ? 0.4 : 1)
    }

    /// Pulses only while somebody is watching; still otherwise.
    @ViewBuilder
    private var halo: some View {
        if live && !reduceMotion {
            PhaseAnimator([false, true]) { on in
                Circle()
                    .fill(colour.opacity(on ? 0 : 0.35))
                    .scaleEffect(on ? 1.9 : 1)
            } animation: { on in on ? .easeOut(duration: 1.6) : .linear(duration: 0.01) }
        } else {
            Circle().fill(colour.opacity(0.22)).scaleEffect(1.45)
        }
    }

    private func batteryColour(_ pct: Int) -> Color {
        pct <= 20 ? Color(hex: 0xFF3B30) : pct <= 50 ? Color(hex: 0xFFB800) : Color(hex: 0x34D399)
    }
}

// MARK: - The Ribbons

enum FamilyRibbonMath {
    struct Sample: Equatable {
        /// Seconds since the window opened.
        let t: Double
        let km: Double
    }

    /// Distance from `home` over the day, split wherever the trail has a gap
    /// longer than the server's own (ten minutes). PURE.
    static func series(trail: [[Double]], home: GeoPoint, start: Double, gap: Double = 600) -> [[Sample]] {
        var out: [[Sample]] = []
        var current: [Sample] = []
        var last: Double?
        for point in trail where point.count >= 3 && point[2] >= start {
            if let last, point[2] - last > gap, !current.isEmpty {
                out.append(current)
                current = []
            }
            let km = FamilyOrbitMath.distanceKm(home, GeoPoint(lat: point[0], lon: point[1]))
            current.append(Sample(t: point[2] - start, km: km))
            last = point[2]
        }
        if !current.isEmpty { out.append(current) }
        return out.filter { $0.count > 1 }
    }

    /// The window: 05:00 today (or the first fix, if somebody was out
    /// earlier) to now.
    static func window(now: Date, trails: [[[Double]]], calendar: Calendar = .current) -> (start: Double, end: Double) {
        let five = calendar.date(bySettingHour: 5, minute: 0, second: 0, of: now) ?? calendar.startOfDay(for: now)
        let earliest = trails.compactMap { $0.first(where: { $0.count >= 3 })?[2] }.min()
        let dayStart = calendar.startOfDay(for: now).timeIntervalSince1970
        let start = min(five.timeIntervalSince1970, max(earliest ?? .infinity, dayStart))
        return (start, max(now.timeIntervalSince1970, start + 3600))
    }

    /// Height, 0…1, on the same log scale for everyone so a hill and a
    /// mountain compare.
    static func height(km: Double, maxKm: Double) -> Double {
        guard maxKm > 0 else { return 0 }
        return min(1, log1p(km / FamilyOrbitMath.knee) / log1p(maxKm / FamilyOrbitMath.knee))
    }
}

/// Today's ribbons, one per person whose day this phone may see.
struct FamilyRibbonsModel: Equatable {
    struct Row: Equatable, Identifiable {
        let subject: String
        let name: String
        let initials: String
        let segments: [[FamilyRibbonMath.Sample]]
        let peakKm: Double
        var id: String { subject }
    }

    let rows: [Row]
    let start: Double
    let end: Double
    let maxKm: Double

    static func make(view: HouseholdView, watch: [WatchedPlace]?, now: Date = Date()) -> FamilyRibbonsModel? {
        let withDays = view.people.filter { ($0.today?.trail.count ?? 0) > 1 }
        guard !withDays.isEmpty else { return nil }
        let homeFix = FamilyOrbitMath.home(people: view.people, watch: watch)
        let window = FamilyRibbonMath.window(now: now, trails: withDays.compactMap { $0.today?.trail })
        let initials = view.initials
        let rows = withDays.compactMap { person -> Row? in
            guard let trail = person.today?.trail,
                  let anchor = homeFix ?? trail.first(where: { $0.count >= 3 }).map({ GeoPoint(lat: $0[0], lon: $0[1]) }) else { return nil }
            let segments = FamilyRibbonMath.series(trail: trail, home: anchor, start: window.start)
            let peak = segments.flatMap { $0 }.map(\.km).max() ?? 0
            return Row(subject: person.subject, name: person.name, initials: initials[person.subject] ?? person.initial,
                       segments: segments, peakKm: peak)
        }
        guard !rows.isEmpty else { return nil }
        let maxKm = max(rows.map(\.peakKm).max() ?? 0, 2)
        return FamilyRibbonsModel(rows: rows, start: window.start, end: window.end, maxKm: maxKm)
    }
}

/// The ridgeline itself. Rows are drawn back to front, each one filling the
/// ground colour under its line first, so a tall ridge in front hides the
/// row behind it — the overlap is what makes it read as a landscape.
struct FamilyRibbonsView: View {
    let model: FamilyRibbonsModel
    let colours: [String: Color]
    var now: Date = Date()
    /// Row pitch. The peaks rise to 1.7 of it, into the row above.
    @ScaledMetric(relativeTo: .body) private var pitch: CGFloat = 26
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let labelWidth: CGFloat = 30
        let height = pitch * CGFloat(model.rows.count) + pitch * 1.4 + 18
        Canvas { context, size in
            let left = labelWidth + 6
            let width = size.width - left - 4
            let span = model.end - model.start
            func x(_ t: Double) -> CGFloat { left + CGFloat(t / span) * width }
            let ground = scheme == .dark ? Color(hex: 0x16143A) : Color.white
            for (index, row) in model.rows.enumerated() {
                let baseline = pitch * 1.4 + pitch * CGFloat(index + 1) - 4
                let colour = colours[row.subject] ?? SR.accent
                // The flat line of a day at home, under everything.
                var flat = Path()
                flat.move(to: CGPoint(x: left, y: baseline))
                flat.addLine(to: CGPoint(x: x(now.timeIntervalSince1970 - model.start), y: baseline))
                context.stroke(flat, with: .color(colour.opacity(0.35)), lineWidth: 1)
                for segment in row.segments {
                    var line = Path()
                    var area = Path()
                    for (i, sample) in segment.enumerated() {
                        let p = CGPoint(x: x(sample.t), y: baseline - CGFloat(FamilyRibbonMath.height(km: sample.km, maxKm: model.maxKm)) * pitch * 1.7)
                        if i == 0 {
                            line.move(to: p)
                            area.move(to: CGPoint(x: p.x, y: baseline))
                            area.addLine(to: p)
                        } else {
                            line.addLine(to: p)
                            area.addLine(to: p)
                        }
                    }
                    if let last = segment.last {
                        area.addLine(to: CGPoint(x: x(last.t), y: baseline))
                    }
                    area.closeSubpath()
                    context.fill(area, with: .color(ground))
                    context.fill(area, with: .linearGradient(
                        Gradient(colors: [colour.opacity(0.75), colour.opacity(0.15)]),
                        startPoint: CGPoint(x: 0, y: baseline - pitch * 1.7), endPoint: CGPoint(x: 0, y: baseline)
                    ))
                    context.stroke(line, with: .color(colour), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                // The person, at the start of their line.
                let dot = Path(ellipseIn: CGRect(x: 2, y: baseline - 12, width: 24, height: 24))
                context.fill(dot, with: .color(colour))
                context.draw(Text(row.initials).font(SR.Text.label(10)).foregroundStyle(.white),
                             at: CGPoint(x: 14, y: baseline), anchor: .center)
            }
            // Hours across the foot, and now.
            let axis = pitch * 1.4 + pitch * CGFloat(model.rows.count) + 4
            let calendar = Calendar.current
            let startDate = Date(timeIntervalSince1970: model.start)
            for hour in stride(from: 6, through: 21, by: 3) {
                guard let tick = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: startDate) else { continue }
                let t = tick.timeIntervalSince1970 - model.start
                guard t >= 0, t <= span else { continue }
                context.draw(Text(String(format: "%02d", hour)).font(SR.Text.mono(10)).foregroundStyle(SR.inkMuted),
                             at: CGPoint(x: x(t), y: axis), anchor: .top)
            }
            let nowX = x(min(span, now.timeIntervalSince1970 - model.start))
            var nowLine = Path()
            nowLine.move(to: CGPoint(x: nowX, y: 6))
            nowLine.addLine(to: CGPoint(x: nowX, y: axis - 2))
            context.stroke(nowLine, with: .color(SR.accent.opacity(0.7)), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
        }
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityIdentifier("family-ribbons")
    }

    private var spoken: String {
        model.rows.map { row in
            row.peakKm < FamilyOrbitMath.homeKm
                ? "\(row.name): at home all day"
                : "\(row.name): furthest \(FamilyOrbitMath.formatKm(row.peakKm)) from home"
        }.joined(separator: ". ")
    }
}
