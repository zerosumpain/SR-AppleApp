import SwiftUI

/// Each trip's forecast, fetched by the phone from Open-Meteo and kept on
/// disk beside the trip, so the day still says what the weather will do
/// with no signal (and says how old the forecast is). Refreshed when the
/// trip is opened online and the forecast is over three hours old.
@MainActor
final class TripWeatherStore: ObservableObject {
    static let shared = TripWeatherStore()

    @Published private(set) var forecasts: [String: TripForecast] = [:]
    private var fetching: Set<String> = []
    private static let staleAfter: TimeInterval = 3 * 3600

    private let folder: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("trip-weather", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private init() {}

    private func file(_ tripId: String) -> URL {
        folder.appendingPathComponent(tripId.replacingOccurrences(of: "/", with: "_") + ".json")
    }

    /// Read from disk: kept apart from `forecasts`, so reading one while a
    /// view draws never publishes a change mid-update.
    private var loaded: [String: TripForecast] = [:]

    func forecast(_ tripId: String) -> TripForecast? {
        if let hit = forecasts[tripId] ?? loaded[tripId] { return hit }
        guard let data = try? Data(contentsOf: file(tripId)),
              let saved = try? JSONDecoder().decode(TripForecast.self, from: data) else { return nil }
        loaded[tripId] = saved
        return saved
    }

    func day(_ tripId: String, _ date: String) -> TripForecast.Day? { forecast(tripId)?.day(date) }

    /// Where the weather is asked for: the first stay, else the first placed wish.
    static func place(_ bundle: TripBundle) -> TripLatLng? {
        bundle.stays.first?.location ?? bundle.wishes.compactMap { $0.place?.location }.first
    }

    func refresh(_ bundle: TripBundle) {
        let id = bundle.trip.id
        guard !SRDemo.isOn, TripNetwork.shared.online, !fetching.contains(id), let place = Self.place(bundle) else { return }
        if let have = forecast(id), let at = ISO8601DateFormatter().date(from: have.fetchedAt),
           Date().timeIntervalSince(at) < Self.staleAfter { return }
        let clock = TripClock(bundle.trip.timeZone)
        let today = clock.localDate(Date())
        guard let window = TripForecast.window(start: bundle.trip.startDate, end: bundle.trip.endDate, today: today,
                                               addingDays: { clock.adding(days: $0, to: $1) }),
              let url = TripForecast.url(place, zone: bundle.trip.timeZone, from: window.from, to: window.to) else { return }
        fetching.insert(id)
        Task {
            defer { fetching.remove(id) }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let forecast = TripForecast.parse(data, place: place, fetchedAt: ISO8601DateFormatter().string(from: Date())) else { return }
            forecasts[id] = forecast
            if let encoded = try? JSONEncoder().encode(forecast) { try? encoded.write(to: file(id), options: .atomic) }
            // The evening-before briefings say the weather: say the new one.
            await TripReminders.sync(Array(TripStore.shared.bundles.values))
        }
    }
}

/// A day's weather and light as a small chip on the map — "☁ 19° · ☂ ·
/// 🌅 17:11" — rather than two lines of text in the drawer. A tap opens it
/// to the full lines: "19° / 12° · Partly cloudy · rain likely 15:00–18:00"
/// and "Sunset 17:11 · golden hour from 16:32".
struct TripDaySky: View {
    let tripId: String
    let date: String
    let bundle: TripBundle
    /// The hours you are out, for the rain line.
    var fromMin: Double = 480
    var toMin: Double = 1320
    @ObservedObject private var weather = TripWeatherStore.shared
    @State private var open = false

    var body: some View {
        let clock = TripClock(bundle.trip.timeZone)
        let sun = TripWeatherStore.place(bundle).flatMap { TripSun.day(date, at: $0, zone: clock.zone) }
        let day = weather.day(tripId, date)
        let rain = day.flatMap { TripWeatherWords.rain($0, fromMin: fromMin, toMin: toMin) }
        if day != nil || sun?.sunsetMin != nil {
            Button {
                SRHaptic.select()
                withAnimation(.snappy(duration: 0.25)) { open.toggle() }
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        if let day {
                            Image(systemName: TripWeatherWords.symbol(day.code))
                                .symbolRenderingMode(.multicolor)
                            if let high = day.highC { Text("\(Int(high.rounded()))°") }
                        }
                        if rain != nil {
                            Image(systemName: "umbrella.fill").foregroundStyle(SR.accentDeep)
                        }
                        if let set = sun?.sunsetMin {
                            Image(systemName: "sun.horizon.fill").foregroundStyle(SR.accent)
                            Text(TripFormat.time(set))
                        }
                    }
                    .font(SR.Text.label(13))
                    .foregroundStyle(SR.ink)
                    if open {
                        ForEach(lines(day, rain: rain, sun: sun), id: \.self) { line in
                            Text(line)
                                .font(SR.Text.secondary(13))
                                .foregroundStyle(SR.inkSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(maxWidth: open ? 260 : nil, alignment: .leading)
                .srGlass(.paper, in: RoundedRectangle(cornerRadius: 18, style: .continuous), interactive: true)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lines(day, rain: rain, sun: sun).joined(separator: ". "))
            .accessibilityHint(open ? "Hides the details" : "Shows the details")
            .accessibilityIdentifier("trip-day-sky")
        }
    }

    private func lines(_ day: TripForecast.Day?, rain: String?, sun: TripSun.Day?) -> [String] {
        var out: [String] = []
        if let day { out.append(([TripWeatherWords.line(day)] + [rain].compactMap { $0 }).joined(separator: " · ")) }
        if let sun, let set = sun.sunsetMin {
            out.append("Sunset \(TripFormat.time(set))" + (sun.goldenMin.map { " · golden hour from \(TripFormat.time($0))" } ?? ""))
        }
        return out
    }
}
