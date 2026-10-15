import Foundation

/// Sunrise, sunset and the golden hour for a place and a local date, worked
/// out on the phone (no service, works offline): NOAA's solar position
/// equations, good to a minute or two at city latitudes.
///
/// Golden hour here is the stretch before sunset when the sun is below 6°,
/// the low warm light photographers mean; "blue hour" is not attempted.
///
/// Foundation only: the Linux harness compiles and tests it.
enum TripSun {
    struct Day: Equatable {
        /// Local minutes after midnight (the trip's zone). Nil in polar day or night.
        var sunriseMin: Double?
        var sunsetMin: Double?
        /// When the evening's golden hour starts (sun at 6°).
        var goldenMin: Double?
    }

    /// The sun on `date` (`YYYY-MM-DD`) at a place, in the zone's local minutes.
    static func day(_ date: String, at place: TripLatLng, zone: TimeZone) -> Day? {
        let parts = date.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let noonUTC = utc.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12)) else { return nil }
        // The zone's offset that day, so the answer is in the trip's local time.
        let offsetMin = Double(zone.secondsFromGMT(for: noonUTC)) / 60
        let jd = noonUTC.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let t = (jd - 2_451_545.0) / 36_525

        // Sun's position (NOAA spreadsheet equations).
        let l0 = (280.46646 + t * (36_000.76983 + t * 0.0003032)).truncatingRemainder(dividingBy: 360)
        let m = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let c = sin(rad(m)) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(rad(2 * m)) * (0.019993 - 0.000101 * t)
            + sin(rad(3 * m)) * 0.000289
        let trueLong = l0 + c
        let omega = 125.04 - 1934.136 * t
        let lambda = trueLong - 0.00569 - 0.00478 * sin(rad(omega))
        let eps0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let eps = eps0 + 0.00256 * cos(rad(omega))
        let decl = deg(asin(sin(rad(eps)) * sin(rad(lambda))))
        let y = pow(tan(rad(eps / 2)), 2)
        let eqTime = 4 * deg(
            y * sin(2 * rad(l0)) - 2 * e * sin(rad(m)) + 4 * e * y * sin(rad(m)) * cos(2 * rad(l0))
                - 0.5 * y * y * sin(4 * rad(l0)) - 1.25 * e * e * sin(2 * rad(m))
        )
        let solarNoonUTCMin = 720 - 4 * place.lng - eqTime

        /// Minutes either side of solar noon when the sun is at `altitude`°.
        func halfArc(_ altitude: Double) -> Double? {
            let zenith = 90 - altitude
            let cosH = (cos(rad(zenith)) - sin(rad(place.lat)) * sin(rad(decl))) / (cos(rad(place.lat)) * cos(rad(decl)))
            guard cosH >= -1, cosH <= 1 else { return nil }
            return 4 * deg(acos(cosH))
        }
        let local = { (utcMin: Double) in utcMin + offsetMin }
        // -0.833°: the sun's upper edge on the horizon, with refraction.
        let rise = halfArc(-0.833).map { local(solarNoonUTCMin - $0) }
        let set = halfArc(-0.833).map { local(solarNoonUTCMin + $0) }
        let golden = halfArc(6).map { local(solarNoonUTCMin + $0) }
        return Day(sunriseMin: rise, sunsetMin: set, goldenMin: golden)
    }

    private static func rad(_ d: Double) -> Double { d * .pi / 180 }
    private static func deg(_ r: Double) -> Double { r * 180 / .pi }
}
