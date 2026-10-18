import Foundation

// MARK: - The sky over Today
//
// Today opens on a short strip of sky that matches the time of day where the
// phone is: pale at noon, amber at dusk, petrol at night. Everything that
// decides what that strip shows lives here, as plain values — which colours
// are how strong, how high the sun stands, what sits on the horizon — so the
// rules are tested without a view and the view only draws.
//
// Foundation only: the Linux harness compiles it with `Trips/TripSun.swift`
// and a three-line `TripLatLng`.

/// How strong each of the sky's five token layers is, 0…1. The view draws
/// each token as its own gradient at this opacity, so a change of light is
/// an opacity change and never a colour mix.
struct SkyLayers: Equatable {
    /// `SR.accentInk`, from the top.
    var petrol: Double
    /// `SR.ink`, from the top.
    var ink: Double
    /// `SR.accentDeep`, a glow on the horizon under the sun.
    var deep: Double
    /// `SR.accent`, a glow round the sun.
    var accent: Double
    /// `SR.warn`, the tight warm glow on the sun.
    var warm: Double

    static let night = SkyLayers(petrol: 0.26, ink: 0.10, deep: 0.04, accent: 0, warm: 0)
    static let twilight = SkyLayers(petrol: 0.16, ink: 0.04, deep: 0.22, accent: 0.14, warm: 0.08)
    static let golden = SkyLayers(petrol: 0.06, ink: 0, deep: 0.18, accent: 0.26, warm: 0.20)
    static let day = SkyLayers(petrol: 0.04, ink: 0, deep: 0, accent: 0.10, warm: 0.14)

    /// Straight-line between two rows; `t` is clamped.
    static func mix(_ a: SkyLayers, _ b: SkyLayers, _ t: Double) -> SkyLayers {
        let t = max(0, min(1, t))
        func lerp(_ x: Double, _ y: Double) -> Double { x + (y - x) * t }
        return SkyLayers(petrol: lerp(a.petrol, b.petrol), ink: lerp(a.ink, b.ink), deep: lerp(a.deep, b.deep),
                         accent: lerp(a.accent, b.accent), warm: lerp(a.warm, b.warm))
    }
}

enum TodaySky {
    /// The horizon runs 05:00 to 23:00 local. Earlier and later are the
    /// night either side of a day, not part of it.
    static let windowStartMin = 300.0
    static let windowEndMin = 1380.0

    /// Where the sky is worked out for, and whether that is a real place.
    ///
    /// A running trip with a place wins: on holiday the sky is the trip's.
    /// Unless the phone's clock is not yet the trip's — the morning of the
    /// flight out the phone is still at home, on home time, and the trip's
    /// sun in home minutes would be an hour or more wrong.
    ///
    /// Otherwise this phone's own last fix. Its latitude always (how long
    /// the day is), its longitude only when it agrees with the zone's offset
    /// to within 25° — a fix the companion took a week ago in another
    /// country must not shift the sunset by hours. `isFix` is true only when
    /// both coordinates came from the fix, and only then are the sunrise and
    /// sunset glyphs drawn: a guessed place can be twenty minutes out.
    ///
    /// No fix at all: London's latitude and the zone's own meridian.
    static func place(
        selfFix: (lat: Double, lon: Double)?,
        trip: TripLatLng?,
        tripZone: TimeZone? = nil,
        zone: TimeZone,
        at date: Date
    ) -> (place: TripLatLng, isFix: Bool) {
        let offset = Double(zone.secondsFromGMT(for: date))
        let meridian = offset / 3600 * 15
        if let trip, tripZone.map({ Double($0.secondsFromGMT(for: date)) == offset }) ?? true {
            return (trip, true)
        }
        guard let fix = selfFix else {
            return (TripLatLng(lat: 51.5, lng: meridian), false)
        }
        // Round the back of the globe: +179° and −179° are two degrees apart.
        let apart = abs((fix.lon - meridian).remainder(dividingBy: 360))
        let plausible = apart <= 25
        return (TripLatLng(lat: fix.lat, lng: plausible ? fix.lon : meridian), plausible)
    }

    /// The sky's layers at a local minute.
    ///
    /// Eight keyframes hung off the day's own sun — night forty minutes
    /// before sunrise, twilight at it, golden just after, full day once the
    /// morning's golden stretch (as long as the evening's) is over, then the
    /// same in reverse into the evening. In between, straight lines. Polar
    /// day or night, where there is no sunrise to hang them on, is day.
    static func layers(minute: Double, sun: TripSun.Day?) -> SkyLayers {
        guard let r = sun?.sunriseMin, let s = sun?.sunsetMin, s > r else { return .day }
        var frames: [(Double, SkyLayers)] = [(r - 40, .night), (r, .twilight), (r + 25, .golden)]
        if let g = sun?.goldenMin {
            let m = s - g
            frames += [(r + m + 30, .day), (g - 30, .day)]
        }
        // A sun that never climbs past 6° has no full day: it goes golden
        // straight to golden.
        frames += [(s - 15, .golden), (s + 10, .twilight), (s + 45, .night)]
        // A short winter day can fold its keyframes over one another; keep
        // them in order by dropping any that would run backwards.
        var ordered: [(Double, SkyLayers)] = []
        for frame in frames where ordered.last.map({ frame.0 >= $0.0 }) ?? true {
            ordered.append(frame)
        }
        guard let first = ordered.first, let last = ordered.last else { return .day }
        if minute <= first.0 { return first.1 }
        if minute >= last.0 { return last.1 }
        for i in 0..<(ordered.count - 1) {
            let (a, b) = (ordered[i], ordered[i + 1])
            guard minute >= a.0, minute < b.0 else { continue }
            let span = b.0 - a.0
            return span > 0 ? SkyLayers.mix(a.1, b.1, (minute - a.0) / span) : b.1
        }
        return last.1
    }

    /// How high the sun stands, 0 on the horizon to 1 at its highest: half
    /// a sine across the daylight. Nothing outside it, and nothing in polar
    /// day or night, which park the sun on the horizon.
    static func lift(minute: Double, sun: TripSun.Day?) -> Double {
        guard let r = sun?.sunriseMin, let s = sun?.sunsetMin, s > r else { return 0 }
        let t = max(0, min(1, (minute - r) / (s - r)))
        return sin(Double.pi * t)
    }
}

// MARK: - The horizon

/// One thing on the line under the sun: when somebody first went out, a stop
/// of the trip running today, sunrise or sunset.
struct HorizonMarker: Identifiable, Equatable {
    enum Kind: Equatable {
        case person(initials: String, out: Bool, subject: String)
        case stop(done: Bool, here: Bool)
        case sunrise
        case sunset
    }

    /// Where a tap on it goes.
    enum Target: Equatable {
        case family
        case tripDay(tripId: String, date: String)
        case none
    }

    /// Stable across minutes: `person-sam`, `stop-w-trevi`, `sunrise`.
    let id: String
    let at: Date
    /// Along the horizon, 0…1.
    let frac: Double
    let kind: Kind
    let target: Target
    /// Read out: "Sam went out at 07:48".
    let spoken: String
    /// The scrub bubble's few words: "Sam out", "Trevi Fountain", "Sunset".
    let short: String
}

/// What the hero is made from, gathered by the view from the stores.
struct TodayHeroInput: Equatable {
    var now: Date
    var zone: TimeZone
    var place: TripLatLng
    var placeIsFix: Bool
    var people: [Person]
    var trip: TripDay?

    struct Person: Equatable {
        let subject: String
        let name: String
        let initials: String
        let isSelf: Bool
        /// "HH:mm" on today's local clock, as the site sends it.
        let firstOut: String?
        /// Out right now (`status == "out"`), not just out earlier.
        let out: Bool
    }

    struct TripDay: Equatable {
        let tripId: String
        let date: String
        let stops: [Stop]
    }

    struct Stop: Equatable {
        let id: String
        let title: String
        let at: Date
        let done: Bool
        let here: Bool
    }
}

/// Everything the hero draws, worked out once a minute. Equatable, so a
/// store publish that changes nothing the sky shows redraws nothing.
struct TodayHeroModel: Equatable {
    /// Now along the horizon, 0…1.
    let nowFrac: Double
    /// The sun's height, 0…1.
    let lift: Double
    let sky: SkyLayers
    let markers: [HorizonMarker]
    /// Today's sun at the hero's place, kept so a scrub can re-tint the sky
    /// for another minute without working the sun out again.
    let sun: TripSun.Day?
    /// The minute of the day: what the once-a-minute ease keys on.
    let minuteKey: Int

    /// Past this many first-outs, the horizon is crowded rather than useful.
    static let peopleLimit = 4
    /// Past this many stops, the six nearest now.
    static let stopLimit = 6

    static func make(_ input: TodayHeroInput) -> TodayHeroModel {
        let calendar = calendar(input.zone)
        let today = localDate(input.now, calendar: calendar)
        // Every minute here is the wall clock's, never time since midnight:
        // the sun's minutes are (TripSun works on the day's own offset), and
        // on the days the clocks change the two are an hour apart from 02:00.
        let minute = wallMinutes(input.now, calendar: calendar)
        let sun = TripSun.day(today, at: input.place, zone: input.zone)

        /// Today's wall-clock minute of an instant; nil for another day's,
        /// which is never on today's line.
        func minutes(_ date: Date) -> Double? {
            localDate(date, calendar: calendar) == today ? wallMinutes(date, calendar: calendar) : nil
        }
        func inWindow(_ m: Double?) -> Bool {
            guard let m else { return false }
            return m >= TodaySky.windowStartMin && m <= TodaySky.windowEndMin
        }
        func clock(_ date: Date) -> String {
            let c = calendar.dateComponents([.hour, .minute], from: date)
            return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
        }

        var markers: [HorizonMarker] = []

        // Who went out, and when: today's first time out of the door, never
        // one still to come (a clock that is wrong, or a fixture's).
        let outings = input.people.compactMap { person -> (TodayHeroInput.Person, Date)? in
            guard let raw = person.firstOut, let m = parseClock(raw),
                  let at = instant(today, minutes: m, zone: input.zone) else { return nil }
            return at <= input.now ? (person, at) : nil
        }
        .sorted { $0.1 == $1.1 ? $0.0.subject < $1.0.subject : $0.1 < $1.1 }
        .prefix(peopleLimit)
        for (person, at) in outings {
            let who = person.isSelf ? "You" : person.name
            markers.append(HorizonMarker(
                id: "person-\(person.subject)", at: at, frac: frac(at, zone: input.zone),
                kind: .person(initials: person.initials, out: person.out, subject: person.subject),
                target: .family,
                spoken: "\(who) went out at \(clock(at))",
                short: "\(who) out"
            ))
        }

        // The running trip's stops inside the window, the six nearest now
        // when there are more, back in time order.
        if let trip = input.trip {
            var stops = trip.stops.filter { inWindow(minutes($0.at)) }
            if stops.count > stopLimit {
                stops = Array(stops.sorted {
                    abs($0.at.timeIntervalSince(input.now)) < abs($1.at.timeIntervalSince(input.now))
                }.prefix(stopLimit))
            }
            for stop in stops.sorted(by: { $0.at < $1.at }) {
                markers.append(HorizonMarker(
                    id: "stop-\(stop.id)", at: stop.at, frac: frac(stop.at, zone: input.zone),
                    kind: .stop(done: stop.done, here: stop.here),
                    target: .tripDay(tripId: trip.tripId, date: trip.date),
                    spoken: stop.done ? "\(stop.title), done" : "\(stop.title) at \(clock(stop.at))",
                    short: stop.title
                ))
            }
        }

        // Sunrise and sunset only from a real place: a guessed one is
        // close enough to colour a sky, not to print a time against.
        if input.placeIsFix, let sun {
            for (key, value, word) in [("sunrise", sun.sunriseMin, "Sunrise"), ("sunset", sun.sunsetMin, "Sunset")] {
                guard let value, inWindow(value), let at = instant(today, minutes: value, zone: input.zone) else { continue }
                markers.append(HorizonMarker(
                    id: key, at: at, frac: frac(at, zone: input.zone),
                    kind: key == "sunrise" ? .sunrise : .sunset,
                    target: .none,
                    spoken: "\(word) \(clock(at))",
                    short: word
                ))
            }
        }

        markers.sort { $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at }
        return TodayHeroModel(
            nowFrac: frac(input.now, zone: input.zone),
            lift: TodaySky.lift(minute: minute, sun: sun),
            sky: TodaySky.layers(minute: minute, sun: sun),
            markers: markers,
            sun: sun,
            minuteKey: Int(minute.rounded(.down))
        )
    }

    /// Along the horizon: 05:00 is 0, 23:00 is 1, and either side clamps.
    /// By the wall clock, so 10:40 sits at 10:40 on a clock-change day too.
    static func frac(_ date: Date, zone: TimeZone) -> Double {
        let minute = wallMinutes(date, calendar: calendar(zone))
        let span = TodaySky.windowEndMin - TodaySky.windowStartMin
        return max(0, min(1, (minute - TodaySky.windowStartMin) / span))
    }

    /// The instant a point along the horizon names, on `now`'s local day.
    static func date(forFrac frac: Double, on now: Date, zone: TimeZone) -> Date {
        let calendar = calendar(zone)
        let span = TodaySky.windowEndMin - TodaySky.windowStartMin
        let minute = TodaySky.windowStartMin + max(0, min(1, frac)) * span
        return instant(localDate(now, calendar: calendar), minutes: minute, zone: zone)
            ?? calendar.startOfDay(for: now).addingTimeInterval(minute * 60)
    }

    /// The instant a wall-clock minute names on a local date (`YYYY-MM-DD`).
    ///
    /// Through the calendar, not by adding minutes to midnight: on the day
    /// the clocks go back 12:30 is 750 minutes on the clock but 810 after
    /// midnight. A time the clocks skip (01:30 on the morning they go
    /// forward) comes out as the calendar resolves it, an hour on.
    static func instant(_ localDate: String, minutes: Double, zone: TimeZone) -> Date? {
        let parts = localDate.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let whole = Int(minutes.rounded(.down))
        let seconds = Int(((minutes - Double(whole)) * 60).rounded())
        return calendar(zone).date(from: DateComponents(
            year: parts[0], month: parts[1], day: parts[2], hour: whole / 60, minute: whole % 60, second: seconds
        ))
    }

    /// Minutes after midnight as the zone's clock reads them, to the second.
    static func wallMinutes(_ date: Date, calendar: Calendar) -> Double {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return Double((c.hour ?? 0) * 60 + (c.minute ?? 0)) + Double(c.second ?? 0) / 60
    }

    /// Minutes after midnight from "HH:mm"; nil for anything else.
    static func parseClock(_ raw: String) -> Double? {
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]),
              (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return Double(h * 60 + m)
    }

    private static func calendar(_ zone: TimeZone) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        return c
    }

    private static func localDate(_ date: Date, calendar: Calendar) -> String {
        let d = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", d.year ?? 0, d.month ?? 0, d.day ?? 0)
    }
}
