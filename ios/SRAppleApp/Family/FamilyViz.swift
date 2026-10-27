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
//
//   The Family tab's Orbit can also turn with the phone (`facing`): the
//   centre is you, the top of the screen is the way you are pointing, and
//   home becomes a marker of its own while you are away from it. Home's tile
//   never turns — a glance at Today wants the same picture every time, and
//   a disc that swings as the phone is lifted reads as broken.
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

    /// A bearing as seen by somebody facing `heading` (both radians, 0 is
    /// north, clockwise), 0..<2π: 0 is straight ahead, π/2 is to the right.
    /// PURE.
    static func relative(_ bearing: Double, facing heading: Double) -> Double {
        let turned = (bearing - heading).truncatingRemainder(dividingBy: 2 * .pi)
        return turned < 0 ? turned + 2 * .pi : turned
    }

    /// The angle closest to `previous` that points the same way as `next`.
    /// PURE.
    ///
    /// A compass reports 359° and then 1°. Animating the disc between those
    /// raw numbers spins it the long way round, a full turn for a two-degree
    /// nudge; animating to 361° moves it the two degrees it actually moved.
    /// So the disc's angle never wraps — it keeps counting.
    static func unwrap(_ next: Double, after previous: Double) -> Double {
        var step = (next - previous).truncatingRemainder(dividingBy: 2 * .pi)
        if step > .pi { step -= 2 * .pi } else if step < -.pi { step += 2 * .pi }
        return previous + step
    }

    /// "ahead and to your right", for VoiceOver in the turning Orbit. PURE.
    ///
    /// Eight ways, like `compass`, and in the words somebody would use
    /// pointing: nobody says "at your two o'clock" to their mum.
    static func relativeWords(_ relative: Double) -> String {
        let names = ["ahead", "ahead and to your right", "to your right", "behind you and to your right",
                     "behind you", "behind you and to your left", "to your left", "ahead and to your left"]
        let turned = self.relative(relative, facing: 0)
        let index = Int(((turned / (2 * .pi)) * 8).rounded()) % 8
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
    /// Built to turn with the phone (`facing`): the centre is you, you are
    /// not one of the planets, and `atHome` means "with you".
    var facing = false
    /// Facing only: whether you are at home yourself, which decides whether
    /// the people round you are "at home" or "with you".
    var youAreHome = false
    /// Facing only, and only while you are away from it: where home is from
    /// you, drawn as a marker of its own.
    var home: Marker? = nil

    struct Marker: Equatable {
        let km: Double
        let bearing: Double
    }

    /// The home marker's key among the bodies `place` spaces apart. Not a
    /// subject the site can send: theirs are ids, never bracketed.
    static let homeSubject = "[home]"

    /// Everything `FamilyOrbitMath.place` spaces apart: the people and, in
    /// the turning Orbit, home — so a planet never sits on the house.
    var bodies: [FamilyOrbitMath.Body] {
        let planets = people.map { FamilyOrbitMath.Body(subject: $0.subject, km: $0.km, bearing: $0.bearing, atHome: $0.atHome) }
        guard let home else { return planets }
        return planets + [FamilyOrbitMath.Body(subject: Self.homeSubject, km: home.km, bearing: home.bearing, atHome: false)]
    }

    static func make(view: HouseholdView, watch: [WatchedPlace]?, now: Date = Date()) -> FamilyOrbitModel? {
        let selfFix = view.people.first(where: \.isSelf)?.position.map { GeoPoint(lat: $0.lat, lon: $0.lon) }
        let homeFix = FamilyOrbitMath.home(people: view.people, watch: watch)
        guard let centre = homeFix ?? selfFix ?? view.placed.first?.position.map({ GeoPoint(lat: $0.lat, lon: $0.lon) }) else {
            return nil
        }
        let (people, outer) = measure(view, from: centre, now: now, including: { _ in true }) { person, km in
            homeFix != nil && (person.status == "home" || km < FamilyOrbitMath.homeKm)
        }
        let missing = view.people.filter { $0.position == nil || $0.status == "off" }.map(\.name)
        return FamilyOrbitModel(people: people, missing: missing, outer: outer, centredOnHome: homeFix != nil)
    }

    /// The turning Orbit's model: centred on you. Nil when this phone has no
    /// fix of its own — the household view's (what the family see) or, failing
    /// that, `device`, the last one iOS has for this phone — and the Family
    /// tab falls back to `make`.
    ///
    /// Bearings stay compass bearings: the view turns the whole disc by the
    /// heading, so the model is rebuilt when somebody moves, not every time
    /// the phone does.
    ///
    /// Your household fix counts only while you are sharing: with sharing
    /// off it is where you were when it stopped. Given both it and `device`,
    /// the newer wins; a `device` fix with no `deviceAt` is a fallback only.
    static func makeFacing(view: HouseholdView, watch: [WatchedPlace]?, device: GeoPoint? = nil,
                           deviceAt: Date? = nil, now: Date = Date()) -> FamilyOrbitModel? {
        let me = view.people.first(where: \.isSelf)
        let shared = me?.status == "off" ? nil : me?.position
        let household = shared.map { GeoPoint(lat: $0.lat, lon: $0.lon) }
        let deviceIsNewer: Bool = {
            guard let deviceAt else { return false }
            guard let at = shared.flatMap({ FamilyPerson.isoDate($0.at) }) else { return true }
            return deviceAt > at
        }()
        guard let centre = (deviceIsNewer ? device : nil) ?? household ?? device else { return nil }
        let homeFix = FamilyOrbitMath.home(people: view.people, watch: watch)
        let homeKm = homeFix.map { FamilyOrbitMath.distanceKm(centre, $0) }
        // The site's "home" is trusted only near home: a status a minute
        // behind a fix that has already left the street is the fix's word
        // against a stale one, and the fix is newer.
        let youAreHome = homeKm.map { $0 < FamilyOrbitMath.homeKm || (me?.status == "home" && $0 < 1) } ?? false
        let marker = homeFix.flatMap { home -> Marker? in
            guard !youAreHome, let km = homeKm else { return nil }
            return Marker(km: km, bearing: FamilyOrbitMath.bearing(from: centre, to: home))
        }
        let (people, outer) = measure(view, from: centre, farthest: marker?.km ?? 0, now: now,
                                      including: { !$0.isSelf }) { person, km in
            km < FamilyOrbitMath.homeKm || (youAreHome && person.status == "home")
        }
        // You are the centre, sharing or not: never "missing" from your own Orbit.
        let missing = view.people.filter { !$0.isSelf && ($0.position == nil || $0.status == "off") }.map(\.name)
        return FamilyOrbitModel(people: people, missing: missing, outer: outer, centredOnHome: false,
                                facing: true, youAreHome: youAreHome, home: marker)
    }

    /// Distance, bearing and tail from `centre` for everyone placed, and the
    /// outer ring that holds them (and `farthest`, for the home marker).
    private static func measure(
        _ view: HouseholdView, from centre: GeoPoint, farthest: Double = 0, now: Date,
        including keep: (FamilyPerson) -> Bool, atHome: (FamilyPerson, Double) -> Bool
    ) -> (people: [Person], outer: Double) {
        let initials = view.initials
        let placed = view.people.filter { $0.position != nil && $0.status != "off" && keep($0) }
        let measured = placed.map { person -> (FamilyPerson, Double, Double) in
            let p = GeoPoint(lat: person.position!.lat, lon: person.position!.lon)
            return (person, FamilyOrbitMath.distanceKm(centre, p), FamilyOrbitMath.bearing(from: centre, to: p))
        }
        let outer = FamilyOrbitMath.outerKm(farthest: max(measured.map { $0.1 }.max() ?? 0, farthest))
        let cutoff = now.timeIntervalSince1970 - 20 * 60
        let people = measured.map { entry -> Person in
            let (person, km, bearing) = entry
            let tail: [CGPoint] = person.moving == nil ? [] : (person.today?.trail ?? [])
                .filter { $0.count >= 3 && $0[2] >= cutoff }
                .map { FamilyOrbitMath.project(GeoPoint(lat: $0[0], lon: $0[1]), home: centre, outer: outer) }
            return Person(
                subject: person.subject, name: person.name,
                initials: initials[person.subject] ?? person.initial,
                isSelf: person.isSelf, km: km, bearing: bearing, atHome: atHome(person, km),
                battery: person.batteryPct, moving: person.moving,
                stale: person.freshness(now: now) == .stale,
                place: person.placeName, tail: tail
            )
        }
        return (people, outer)
    }

    /// "Sam, 2.4 km north-east of home, walking, battery 54%" — or, in the
    /// turning Orbit with a `heading` (radians), "Sam, 2.4 km ahead and to
    /// your right, walking, battery 54%".
    func spoken(_ person: Person, heading: Double? = nil) -> String {
        var parts = [person.isSelf ? "You" : person.name]
        if person.atHome {
            parts.append(facing && !youAreHome ? "with you" : "at home")
        } else {
            parts.append("\(FamilyOrbitMath.formatKm(person.km)) \(direction(person.bearing, heading: heading))")
            if let place = person.place {
                // Somebody at home while you are out: home is where they are.
                if place != "Home" { parts.append("near \(place)") } else if facing { parts.append("at home") }
            }
        }
        if let moving = person.moving { parts.append(moving.verb) }
        if let battery = person.battery { parts.append("battery \(battery)%") }
        if person.stale { parts.append("not seen lately") }
        return parts.joined(separator: ", ")
    }

    /// "Home, 3.1 km behind you". Nil while there is no home marker.
    func spokenHome(heading: Double? = nil) -> String? {
        home.map { "Home, \(FamilyOrbitMath.formatKm($0.km)) \(direction($0.bearing, heading: heading))" }
    }

    /// "ahead and to your right" with a heading, "north-east of you" facing
    /// but without one (no compass), "north-east of home" otherwise.
    private func direction(_ bearing: Double, heading: Double?) -> String {
        if facing, let heading {
            return FamilyOrbitMath.relativeWords(FamilyOrbitMath.relative(bearing, facing: heading))
        }
        return "\(FamilyOrbitMath.compass(bearing)) of \(centredOnHome ? "home" : "you")"
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
/// The rings and the tails are `Canvas`es (drawn once per change, no layers),
/// the people are views — each one a VoiceOver element and a tap target.
/// Nothing moves while idle: the one animation is the halo round somebody on
/// the move, and only while `live`.
///
/// Given a `heading`, the picture turns with the phone. The rings are circles
/// and do not need to, so they stay put with their labels upright; the tails,
/// the north tick and the planets are one layer that rotates as a whole, and
/// each planet turns back by the same angle so its initials stay level. A
/// rotation is a render transform: turning the phone redraws neither Canvas.
struct FamilyOrbitView: View {
    let model: FamilyOrbitModel
    let colours: [String: Color]
    /// On screen and the app in front: the moving halo may pulse.
    var live: Bool = false
    /// Which way the phone points, radians from north, unwrapped (see
    /// `FamilyOrbitMath.unwrap`). Nil is north up — Home's tile, always.
    var heading: Double? = nil
    /// A planet tapped; nil leaves the whole view to the caller's tap.
    var openPerson: ((String) -> Void)? = nil
    @ScaledMetric(relativeTo: .body) private var planet: CGFloat = 34
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let radius = side / 2 - planet * 0.6
            let centre = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let placed = Dictionary(FamilyOrbitMath.place(
                model.bodies,
                outer: model.outer,
                separation: Double(planet * 1.1 / max(radius, 1))
            ).map { ($0.subject, $0) }, uniquingKeysWith: { first, _ in first })
            let turn = heading ?? 0

            ZStack {
                OrbitRings(outer: model.outer, centre: centre, radius: radius, dark: scheme == .dark)
                    .equatable()
                if heading != nil {
                    OrbitAhead(centre: centre, radius: radius).equatable()
                }
                // Everything that turns with the phone.
                ZStack {
                    north(centre: centre, radius: radius, upright: turn)
                    OrbitTails(people: model.people, colours: colours, centre: centre, radius: radius)
                        .equatable()
                    sun
                        .rotationEffect(.radians(turn))
                        .position(centre)
                    if let marker = model.home, let spot = placed[FamilyOrbitModel.homeSubject] {
                        homeMarker(marker)
                            .rotationEffect(.radians(turn))
                            .position(x: centre.x + spot.x * radius, y: centre.y + spot.y * radius)
                    }
                    ForEach(model.people) { person in
                        if let spot = placed[person.subject] {
                            planetView(person)
                                .rotationEffect(.radians(turn))
                                .position(x: centre.x + spot.x * radius, y: centre.y + spot.y * radius)
                        }
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
                .rotationEffect(.radians(-turn))
                // No animation into or out of north up: the angle is unwrapped
                // and may be several turns round, and easing from there to 0
                // would spin the disc that many times.
                .animation(reduceMotion || heading == nil ? nil : .easeOut(duration: 0.35), value: turn)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("family-orbit")
    }

    /// North, on the rim. It sits at the top until the disc turns, and then
    /// it is wherever north actually is; the letter itself stays level.
    private func north(centre: CGPoint, radius: CGFloat, upright turn: Double) -> some View {
        Text("N")
            .font(SR.Text.label(10))
            .foregroundStyle(SR.inkMuted)
            .rotationEffect(.radians(turn))
            // Bottom-aligned in a box whose foot is just above the rim: the
            // letter's own height scales with the reader's text size.
            .frame(width: 40, height: 40, alignment: .bottom)
            .position(x: centre.x, y: centre.y - radius - 2 - 20)
            .accessibilityHidden(true)
    }

    private var sun: some View {
        let symbol = model.centredOnHome ? "house.fill" : model.facing && heading != nil ? "location.north.fill" : "location.fill"
        return ZStack {
            Circle()
                .fill(SR.Hue.family.gradient)
                .frame(width: planet * 1.25, height: planet * 1.25)
                .shadow(color: SR.Hue.family.glow.opacity(0.55), radius: 14)
            Image(systemName: symbol)
                .font(.system(size: planet * 0.45, weight: .bold))
                .foregroundStyle(.white)
        }
        .accessibilityLabel(sunLabel)
    }

    private var sunLabel: String {
        guard !model.centredOnHome else { return "Home" }
        guard model.facing, let heading else { return "You" }
        return "You, facing \(FamilyOrbitMath.compass(FamilyOrbitMath.relative(heading, facing: 0)))"
    }

    /// Home, while you are away from it: a small sun of its own, at its own
    /// distance and direction from you.
    private func homeMarker(_ marker: FamilyOrbitModel.Marker) -> some View {
        ZStack {
            Circle()
                .fill(SR.Hue.family.gradient)
                .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 2))
                .shadow(color: SR.Hue.family.glow.opacity(0.45), radius: 6, y: 2)
            Image(systemName: "house.fill")
                .font(.system(size: planet * 0.34, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: planet * 0.8, height: planet * 0.8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.spokenHome(heading: heading) ?? "Home")
        .accessibilityIdentifier("orbit-home")
    }

    @ViewBuilder
    private func planetView(_ person: FamilyOrbitModel.Person) -> some View {
        let colour = colours[person.subject] ?? SR.accent
        let disc = OrbitPlanet(person: person, colour: colour, size: planet, live: live)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(model.spoken(person, heading: heading))
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

/// The disc, its rings and their labels. Equatable, so a new heading — or
/// anything else that redraws the Orbit without changing the scale — does
/// not repaint it.
struct OrbitRings: View, Equatable {
    let outer: Double
    let centre: CGPoint
    let radius: CGFloat
    let dark: Bool

    var body: some View {
        let marks = FamilyOrbitMath.rings(outer: outer)
        let lineColour = SR.ink.opacity(dark ? 0.16 : 0.10)
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
        }
        .accessibilityHidden(true)
    }
}

/// Tails: the last twenty minutes behind anybody on the move, fading towards
/// where they were. In the layer that turns, so they point the way the
/// planets do.
struct OrbitTails: View, Equatable {
    let people: [FamilyOrbitModel.Person]
    let colours: [String: Color]
    let centre: CGPoint
    let radius: CGFloat

    var body: some View {
        Canvas { context, _ in
            for person in people where person.tail.count > 1 {
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
}

/// Ahead, in the turning Orbit: a soft beam up from the centre and a notch at
/// the top of the rim. It never turns — ahead is always the top of the
/// screen — which is what makes the rest of the picture read as turning.
struct OrbitAhead: View, Equatable {
    let centre: CGPoint
    let radius: CGFloat

    var body: some View {
        Canvas { context, _ in
            var beam = Path()
            beam.move(to: centre)
            beam.addArc(center: centre, radius: radius, startAngle: .degrees(-90 - 22), endAngle: .degrees(-90 + 22), clockwise: false)
            beam.closeSubpath()
            context.fill(beam, with: .linearGradient(
                Gradient(colors: [SR.accent.opacity(0.18), SR.accent.opacity(0)]),
                startPoint: centre, endPoint: CGPoint(x: centre.x, y: centre.y - radius)
            ))
            var notch = Path()
            notch.move(to: CGPoint(x: centre.x, y: centre.y - radius + 1))
            notch.addLine(to: CGPoint(x: centre.x - 6, y: centre.y - radius + 10))
            notch.addLine(to: CGPoint(x: centre.x + 6, y: centre.y - radius + 10))
            notch.closeSubpath()
            context.fill(notch, with: .color(SR.accent))
        }
        .accessibilityHidden(true)
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
    /// Room under the rows for the hours: it grows with their type, or the
    /// larger text sizes cut the hours off at the foot of the tile.
    @ScaledMetric(relativeTo: .caption) private var axisRoom: CGFloat = 18
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let labelWidth: CGFloat = 30
        let height = pitch * CGFloat(model.rows.count) + pitch * 1.4 + axisRoom
        Canvas { context, size in
            let left = labelWidth + 6
            let width = size.width - left - 4
            let span = model.end - model.start
            func x(_ t: Double) -> CGFloat { left + CGFloat(t / span) * width }
            let ground = SR.surface
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
