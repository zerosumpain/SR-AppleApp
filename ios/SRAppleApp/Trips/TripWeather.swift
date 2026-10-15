import Foundation

/// The weather for a trip's days (v7, sense of place), from Open-Meteo's
/// free forecast — no key, nothing of the trip sent but a point and dates.
/// Fetched by the phone and kept with the trip, so a day says "19° / 12° ·
/// rain likely 15:00–18:00" offline too, with when it was forecast.
///
/// Foundation only: the Linux harness compiles and tests it.
struct TripForecast: Codable, Equatable {
    struct Hour: Codable, Equatable {
        /// Local minutes after midnight.
        var min: Double
        var tempC: Double?
        /// Chance of rain, per cent.
        var rain: Double?
        var code: Int?
    }

    struct Day: Codable, Equatable {
        var date: String
        var highC: Double?
        var lowC: Double?
        var rain: Double?
        var code: Int?
        var hours: [Hour]
    }

    var place: TripLatLng
    var days: [Day]
    /// When it was fetched (ISO 8601).
    var fetchedAt: String

    func day(_ date: String) -> Day? { days.first { $0.date == date } }

    /// Open-Meteo's `/v1/forecast` answer (daily + hourly, in the trip's zone).
    static func parse(_ data: Data, place: TripLatLng, fetchedAt: String) -> TripForecast? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let daily = root["daily"] as? [String: Any],
              let dates = daily["time"] as? [String] else { return nil }
        func nums(_ obj: [String: Any]?, _ key: String) -> [Double?] {
            ((obj?[key] as? [Any]) ?? []).map { ($0 as? NSNumber)?.doubleValue }
        }
        let highs = nums(daily, "temperature_2m_max"), lows = nums(daily, "temperature_2m_min")
        let rains = nums(daily, "precipitation_probability_max"), codes = nums(daily, "weather_code")
        let hourly = root["hourly"] as? [String: Any]
        let times = (hourly?["time"] as? [String]) ?? []
        let hTemp = nums(hourly, "temperature_2m"), hRain = nums(hourly, "precipitation_probability"), hCode = nums(hourly, "weather_code")
        var byDate: [String: [Hour]] = [:]
        for (i, t) in times.enumerated() {
            // "2026-10-27T15:00"
            let parts = t.split(separator: "T")
            guard parts.count == 2 else { continue }
            let hm = parts[1].split(separator: ":").compactMap { Double($0) }
            guard hm.count >= 2 else { continue }
            func at(_ a: [Double?]) -> Double? { i < a.count ? a[i] : nil }
            byDate[String(parts[0]), default: []].append(Hour(min: hm[0] * 60 + hm[1], tempC: at(hTemp), rain: at(hRain), code: at(hCode).map { Int($0) }))
        }
        let days = dates.enumerated().map { i, date -> Day in
            func at(_ a: [Double?]) -> Double? { i < a.count ? a[i] : nil }
            return Day(date: date, highC: at(highs), lowC: at(lows), rain: at(rains), code: at(codes).map { Int($0) }, hours: byDate[date] ?? [])
        }
        return days.isEmpty ? nil : TripForecast(place: place, days: days, fetchedAt: fetchedAt)
    }

    /// Open-Meteo forecasts 16 days: the part of the trip inside that, or nil.
    static func window(start: String, end: String, today: String, addingDays: (Int, String) -> String?) -> (from: String, to: String)? {
        guard let last = addingDays(15, today) else { return nil }
        let from = max(start, today)
        let to = min(end, last)
        return from <= to ? (from, to) : nil
    }

    static func url(_ place: TripLatLng, zone: String, from: String, to: String) -> URL? {
        var c = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        c?.queryItems = [
            URLQueryItem(name: "latitude", value: String(format: "%.4f", place.lat)),
            URLQueryItem(name: "longitude", value: String(format: "%.4f", place.lng)),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "hourly", value: "temperature_2m,precipitation_probability,weather_code"),
            URLQueryItem(name: "timezone", value: zone),
            URLQueryItem(name: "start_date", value: from),
            URLQueryItem(name: "end_date", value: to),
        ]
        return c?.url
    }
}

enum TripWeatherWords {
    /// WMO weather codes in a word or two.
    static func words(_ code: Int?) -> String {
        switch code ?? -1 {
        case 0: return "Clear"
        case 1: return "Mostly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55, 56, 57: return "Drizzle"
        case 61, 63, 66, 80, 81: return "Rain"
        case 65, 67, 82: return "Heavy rain"
        case 71, 73, 75, 77, 85, 86: return "Snow"
        case 95, 96, 99: return "Thunderstorms"
        default: return "—"
        }
    }

    static func symbol(_ code: Int?) -> String {
        switch code ?? -1 {
        case 0: return "sun.max"
        case 1, 2: return "cloud.sun"
        case 3: return "cloud"
        case 45, 48: return "cloud.fog"
        case 51, 53, 55, 56, 57: return "cloud.drizzle"
        case 61, 63, 66, 80, 81: return "cloud.rain"
        case 65, 67, 82: return "cloud.heavyrain"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow"
        case 95, 96, 99: return "cloud.bolt.rain"
        default: return "thermometer.medium"
        }
    }

    /// "19° / 12° · Partly cloudy".
    static func line(_ day: TripForecast.Day) -> String {
        var parts: [String] = []
        if let hi = day.highC, let lo = day.lowC { parts.append("\(Int(hi.rounded()))° / \(Int(lo.rounded()))°") }
        parts.append(words(day.code))
        return parts.joined(separator: " · ")
    }

    /// "Rain likely 15:00–18:00", over the hours of the day you are out
    /// (`fromMin`…`toMin`) where the chance is 50 % or more; nil when dry.
    static func rain(_ day: TripForecast.Day, fromMin: Double = 0, toMin: Double = 1440) -> String? {
        let wet = day.hours.filter { $0.min >= fromMin - 30 && $0.min <= toMin && ($0.rain ?? 0) >= 50 }.map(\.min).sorted()
        guard let first = wet.first, let last = wet.last else { return nil }
        let hhmm = { (m: Double) in String(format: "%02d:00", Int(m / 60) % 24) }
        return first == last ? "Rain likely around \(hhmm(first))" : "Rain likely \(hhmm(first))–\(hhmm(last + 60))"
    }
}
