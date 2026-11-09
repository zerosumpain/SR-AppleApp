import Foundation

// Somebody moving, drawn moving.
//
// The family map used to put each pin where the newest fix said and leave it
// there until the next read: on foot it hopped every five seconds, on close
// tracking every thirty, and after a dead patch it jumped straight across
// whatever the queued route went round (review 2026-11-09, O2).
//
// What the map draws now is a PLAYBACK of each person's recent path, a few
// seconds behind real time — the way a video buffers. Behind the newest fix
// there is always a recorded point on either side to interpolate between, so
// the pin glides along the road the phone actually took. Three things keep it
// honest:
//
// - **Outliers are dropped** (`LiveTrack.merge`): a fix implying more than
//   250 km/h from the last good one is a GPS jump, unless the fix after it
//   agrees with it (then it is a real relocation, and the track follows).
// - **Past the newest fix it dead-reckons, briefly** (`position(at:)`): along
//   the last heading at the last speed, slowing to a stop over 15 s, so a late
//   read does not freeze a car mid-junction — and never further.
// - **A backlog is fast-forwarded** (`LivePlayhead`): a phone that comes back
//   from no signal sends minutes of route at once; the playhead is then far
//   behind and covers the gap in about two seconds, along the route, instead
//   of teleporting.
//
// Corrections are eased (`LiveSmoother`) so a fix that lands somewhere the
// dead reckoning did not expect pulls the pin over rather than snapping it.
//
// PURE and Foundation-only: every rule is a Linux unit test
// (`FamilyLiveMotionTests`, `scripts/home-check.sh`).

/// One fix: where, and when (seconds since 1970).
struct LiveSample: Equatable {
    let t: Double
    let lat: Double
    let lon: Double
}

/// Short-range geometry: an equirectangular approximation, exact to well
/// under a metre across the few hundred metres between two live fixes.
enum LiveGeo {
    static let metresPerDegree = 111_320.0

    static func metres(_ a: LiveSample, _ b: LiveSample) -> Double {
        let x = (b.lon - a.lon) * cos((a.lat + b.lat) / 2 * .pi / 180) * metresPerDegree
        let y = (b.lat - a.lat) * metresPerDegree
        return (x * x + y * y).squareRoot()
    }

    /// Compass bearing from `a` to `b`, degrees: 0 north, clockwise.
    static func bearing(_ a: LiveSample, _ b: LiveSample) -> Double {
        let x = (b.lon - a.lon) * cos((a.lat + b.lat) / 2 * .pi / 180)
        let y = b.lat - a.lat
        let d = atan2(x, y) * 180 / .pi
        return d < 0 ? d + 360 : d
    }

    /// `metres` from (lat, lon) along `bearing` degrees.
    static func offset(lat: Double, lon: Double, metres: Double, bearing: Double) -> (lat: Double, lon: Double) {
        let r = bearing * .pi / 180
        let dLat = metres * cos(r) / metresPerDegree
        let dLon = metres * sin(r) / (metresPerDegree * max(0.01, cos(lat * .pi / 180)))
        return (lat + dLat, lon + dLon)
    }
}

/// One person's recent path, cleaned and in time order. PURE.
struct LiveTrack: Equatable {
    private(set) var samples: [LiveSample] = []

    /// How much path is kept behind the newest fix.
    static let keep: Double = 300
    /// Faster than this between two fixes is a GPS jump (250 km/h).
    static let maxSpeed: Double = 70
    /// How far past the newest fix the pin carries on, at most.
    static let extrapolate: Double = 15
    /// Slower than this is standing about: nothing to carry on with.
    static let minCarrySpeed: Double = 0.5

    var newest: LiveSample? { samples.last }

    /// Fold new fixes in: time order, one per instant, nothing from the
    /// future, nothing older than `keep` behind the newest, outliers out.
    mutating func merge(_ incoming: [LiveSample], now: Double) {
        guard !incoming.isEmpty else { return }
        var byTime: [Double: LiveSample] = [:]
        for s in samples + incoming where s.t <= now + 60 && s.lat.isFinite && s.lon.isFinite {
            byTime[s.t] = s
        }
        let ordered = byTime.values.sorted { $0.t < $1.t }
        guard let last = ordered.last else { samples = []; return }
        let fresh = ordered.filter { $0.t >= last.t - Self.keep }
        samples = Self.withoutJumps(fresh)
    }

    /// Drop a fix that is too far from the last good one to have been
    /// reached — unless the fix after it agrees with it, which makes it a
    /// real move (a phone that slept on a train wakes miles on).
    static func withoutJumps(_ points: [LiveSample]) -> [LiveSample] {
        func speed(_ a: LiveSample, _ b: LiveSample) -> Double {
            let dt = b.t - a.t
            return dt > 0 ? LiveGeo.metres(a, b) / dt : .infinity
        }
        var kept: [LiveSample] = []
        for (i, p) in points.enumerated() {
            guard let k = kept.last else { kept.append(p); continue }
            if speed(k, p) <= maxSpeed { kept.append(p); continue }
            if i + 1 < points.count {
                let q = points[i + 1]
                if speed(p, q) <= maxSpeed && speed(k, q) > maxSpeed { kept.append(p) }
            }
        }
        return kept
    }

    /// Where the track says the person was at `t`, and which way they were
    /// heading (degrees, nil when still). Between fixes: along the line
    /// joining them. Before the first: the first. After the newest: carried
    /// on along the last leg at its speed, easing to a stop over `extrapolate`
    /// seconds. Nil with no fixes.
    func position(at t: Double) -> (lat: Double, lon: Double, heading: Double?)? {
        guard let first = samples.first, let last = samples.last else { return nil }
        if t <= first.t { return (first.lat, first.lon, nil) }
        if t >= last.t {
            guard samples.count >= 2 else { return (last.lat, last.lon, nil) }
            let prev = samples[samples.count - 2]
            let dt = last.t - prev.t
            let leg = LiveGeo.metres(prev, last)
            guard dt > 0, dt <= 30, leg / dt >= Self.minCarrySpeed else {
                return (last.lat, last.lon, leg > 2 ? LiveGeo.bearing(prev, last) : nil)
            }
            let heading = LiveGeo.bearing(prev, last)
            let ahead = min(t - last.t, Self.extrapolate)
            // Constant deceleration to zero at `extrapolate`: v·a·(1 − a/2E).
            let travel = (leg / dt) * ahead * (1 - ahead / (2 * Self.extrapolate))
            let p = LiveGeo.offset(lat: last.lat, lon: last.lon, metres: travel, bearing: heading)
            return (p.lat, p.lon, heading)
        }
        // Binary search for the leg that holds t.
        var lo = 0, hi = samples.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if samples[mid].t <= t { lo = mid } else { hi = mid }
        }
        let a = samples[lo], b = samples[hi]
        let f = b.t > a.t ? (t - a.t) / (b.t - a.t) : 1
        let heading: Double? = LiveGeo.metres(a, b) > 2 ? LiveGeo.bearing(a, b) : nil
        return (a.lat + (b.lat - a.lat) * f, a.lon + (b.lon - a.lon) * f, heading)
    }

    /// The fixes between two instants, for the fading line behind the pin.
    func path(from: Double, to: Double) -> [LiveSample] {
        samples.filter { $0.t >= from && $0.t <= to }
    }

    /// Speed over the last leg, m/s; nil without two fixes.
    var speed: Double? {
        guard samples.count >= 2 else { return nil }
        let a = samples[samples.count - 2], b = samples[samples.count - 1]
        return b.t > a.t ? LiveGeo.metres(a, b) / (b.t - a.t) : nil
    }

    /// Whether this track has moved lately: a fix in the last `window`
    /// seconds and more than `metres` covered across them.
    func isMoving(now: Double, window: Double = 120, metres: Double = 25) -> Bool {
        let recent = samples.filter { $0.t >= now - window }
        guard let a = recent.first, let b = recent.last, recent.count >= 2 else { return false }
        return LiveGeo.metres(a, b) >= metres || recent.indices.dropFirst().reduce(0) { $0 + LiveGeo.metres(recent[$1 - 1], recent[$1]) } >= metres
    }
}

/// Which instant of a track is drawn. PURE.
///
/// Runs at real speed `lag` seconds behind the clock, so there is nearly
/// always a recorded fix ahead of it. When it is far behind — a backlog just
/// arrived — it speeds up to cover the gap in `catchUp` seconds.
struct LivePlayhead: Equatable {
    /// The track time being drawn.
    var at: Double
    /// The wall clock at the last advance.
    var wall: Double

    /// Behind real time: the phone's 5 s upload plus the viewer's 5 s read,
    /// less a little, so the pin is nearly always between two real fixes.
    static let lag: Double = 8
    /// Further behind than this is a backlog: fast-forward.
    static let behind: Double = 10
    /// How long a fast-forward takes, whatever the gap.
    static let catchUp: Double = 2.5

    /// Starts at the newest fix (no replay of history on opening the map),
    /// or where real time minus the lag is, whichever is earlier.
    static func start(now: Double, newest: Double) -> LivePlayhead {
        LivePlayhead(at: min(newest, now - lag), wall: now)
    }

    mutating func advance(now: Double) {
        let target = now - Self.lag
        let dt = max(0, min(now - wall, 1))
        wall = now
        let gap = target - at
        if gap > Self.behind {
            at += max(dt, dt * gap / Self.catchUp)
        } else {
            at += dt
        }
        at = min(at, target)
    }

    /// Fast-forwarding a backlog right now.
    var catchingUp: Bool { wall - Self.lag - at > Self.behind }
}

/// Eases the drawn point towards the computed one, so a correction slides
/// rather than snaps. A big jump (over `snap` metres: a relocation, or the
/// first frame) is taken at once. PURE.
struct LiveSmoother: Equatable {
    var lat: Double
    var lon: Double
    /// Seconds for the drawn point to close ~63% of the distance.
    static let timeConstant = 0.35
    static let snap = 400.0

    mutating func step(toward target: (lat: Double, lon: Double), dt: Double) {
        let here = LiveSample(t: 0, lat: lat, lon: lon), there = LiveSample(t: 0, lat: target.lat, lon: target.lon)
        if LiveGeo.metres(here, there) > Self.snap || dt <= 0 {
            lat = target.lat; lon = target.lon
            return
        }
        let k = 1 - exp(-dt / Self.timeConstant)
        lat += (target.lat - lat) * k
        lon += (target.lon - lon) * k
    }
}

/// What the map draws for one person on one frame.
struct LiveFrame: Equatable {
    let lat: Double
    let lon: Double
    /// Degrees from north, nil when still.
    let heading: Double?
    /// The last minute of path up to the drawn point, oldest first.
    let tail: [LiveSample]
    /// Metres per second over the last leg.
    let speed: Double?
    /// Fast-forwarding through a backlog.
    let catchingUp: Bool
}

/// Everyone's tracks, playheads and drawn points. PURE: the map owns one and
/// feeds it reads (`ingest`) and frames (`frame`).
struct FamilyLiveState: Equatable {
    struct Entry: Equatable {
        var track = LiveTrack()
        var playhead: LivePlayhead?
        var shown: LiveSmoother?
        /// When this person last had a live point at all, wall clock.
        var heardAt: Double = 0
    }

    private(set) var entries: [String: Entry] = [:]

    /// How long a track stays live after its newest fix.
    static let liveFor: Double = 180
    static let tailSeconds: Double = 60

    /// Fold one read into a person's track: the overlay's recent path, and
    /// the pin's own position (which may be newer, or all there is).
    mutating func ingest(subject: String, samples: [LiveSample], now: Double) {
        guard !samples.isEmpty else { return }
        var entry = entries[subject] ?? Entry()
        entry.track.merge(samples, now: now)
        entry.heardAt = now
        entries[subject] = entry
    }

    /// Forget whoever is no longer in the view.
    mutating func keep(only subjects: Set<String>) {
        entries = entries.filter { subjects.contains($0.key) }
    }

    /// Whether anyone should be animated now: a newest fix within `liveFor`
    /// and movement across the last two minutes.
    func animating(now: Double) -> Bool {
        entries.values.contains { e in
            guard let newest = e.track.newest else { return false }
            return now - newest.t <= Self.liveFor && e.track.isMoving(now: newest.t + 1)
        }
    }

    /// Whether this person is drawn by playback (and not at their static pin).
    func isLive(_ subject: String, now: Double) -> Bool {
        guard let e = entries[subject], let newest = e.track.newest else { return false }
        return now - newest.t <= Self.liveFor && e.track.isMoving(now: newest.t + 1)
    }

    /// Advance everyone to wall-clock `now` and say where to draw each live
    /// person. Somebody not live gets no frame (the map draws their pin).
    mutating func frame(now: Double) -> [String: LiveFrame] {
        var out: [String: LiveFrame] = [:]
        for (subject, var e) in entries {
            guard isLive(subject, now: now), let newest = e.track.newest else {
                e.playhead = nil; e.shown = nil
                entries[subject] = e
                continue
            }
            var head = e.playhead ?? LivePlayhead.start(now: now, newest: newest.t)
            let dt = e.playhead.map { max(0, now - $0.wall) } ?? 0
            head.advance(now: now)
            guard let p = e.track.position(at: head.at) else { continue }
            var shown = e.shown ?? LiveSmoother(lat: p.lat, lon: p.lon)
            shown.step(toward: (p.lat, p.lon), dt: head.catchingUp ? 0 : dt)
            e.playhead = head
            e.shown = shown
            entries[subject] = e
            let tail = e.track.path(from: head.at - Self.tailSeconds, to: head.at)
                + [LiveSample(t: head.at, lat: shown.lat, lon: shown.lon)]
            out[subject] = LiveFrame(lat: shown.lat, lon: shown.lon, heading: p.heading, tail: tail,
                                     speed: e.track.speed, catchingUp: head.catchingUp)
        }
        return out
    }
}
