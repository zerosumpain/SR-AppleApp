import Foundation
import Combine

// MARK: - /health's summary intelligence
//
// The digest SR-Health writes for the phone (`GET /api/health/hub`, passed
// through by SR-Main at `/api/native/health/hub`). Every number AND every
// sentence is decided there, by the code that owns them — the phone renders and
// never re-derives. It cannot know that a falling RHR is good and a falling HRV
// is not, and it should not try.
//
// Every section can be missing on its own: one service failing on the server
// costs its own section, as it does on the page.

enum HubTone: String, Decodable {
    case good, watch, bad, none

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = HubTone(rawValue: raw) ?? .none
    }
}

struct HubDigest: Decodable {
    struct Readiness: Decodable, Hashable {
        struct Factor: Decodable, Hashable, Identifiable {
            let key: String
            let label: String
            let score: Double
            let weight: Double
            var id: String { key }
        }
        let score: Double
        let label: String
        let recommendation: String
        let factors: [Factor]
    }

    struct Planner: Decodable, Hashable {
        let headline: String
        let detail: String?
    }

    struct Tile: Decodable, Hashable, Identifiable {
        let key: String
        let label: String
        let display: String
        let unit: String?
        let foot: String?
        let tone: HubTone
        let series: [Double]
        var id: String { key }
    }

    struct Instrument: Decodable, Hashable, Identifiable {
        let key: String
        let label: String
        let window: String
        let display: String
        let unit: String?
        let tone: HubTone
        let reading: String
        let meaning: String
        var id: String { key }
    }

    struct Forecast: Decodable, Hashable, Identifiable {
        struct Point: Decodable, Hashable { let date: String; let value: Double }
        struct ConePoint: Decodable, Hashable { let date: String; let value: Double; let low: Double; let high: Double }
        let key: String
        let label: String
        let unit: String?
        let horizonDays: Int
        let now: Double?
        let projected: Double?
        let low: Double?
        let high: Double?
        let reading: String
        let history: [Point]
        let cone: [ConePoint]
        var id: String { key }
    }

    struct Move: Decodable, Hashable, Identifiable {
        let rank: Int
        let title: String
        let buys: String
        let costs: String
        let leverage: String
        var id: Int { rank }
    }

    struct Tripwire: Decodable, Hashable, Identifiable {
        let key: String
        let state: String
        let signal: String
        let window: String
        let trigger: String
        let now: String
        let meaning: String
        var id: String { key }

        var tripped: Bool { state == "tripped" }
        var close: Bool { state == "close" }
        /// The ones worth a line on the main tab.
        var live: Bool { tripped || close }
    }

    struct Segments: Decodable, Hashable {
        struct Gettable: Decodable, Hashable, Identifiable {
            let name: String
            let gapPct: Double
            let detail: String?
            var id: String { name }
        }
        let improving: Int
        let holding: Int
        let slipping: Int
        let noRead: Int
        let gettable: [Gettable]
    }

    struct Plan: Decodable, Hashable {
        struct Evidence: Decodable, Hashable, Identifiable {
            let label: String
            let display: String
            var id: String { label }
        }
        let sport: String
        let headline: String
        let why: [String]
        let evidence: [Evidence]
    }

    struct Experiment: Decodable, Hashable, Identifiable {
        let status: String
        let title: String
        let change: String
        let hold: String
        let measure: String
        let stop: String
        let counter: String?
        var id: String { title }
        var live: Bool { status == "live" }
    }

    struct Verdict: Decodable, Hashable {
        let headline: [String]
        let body: [String]
        let quote: String?
        let reviewOn: String?
    }

    let generatedAt: String
    let syncedAgoSeconds: Int
    let isMock: Bool
    let lede: String?
    let readiness: Readiness?
    let planner: Planner?
    let tiles: [Tile]
    let instruments: [Instrument]
    let forecasts: [Forecast]
    let moves: [Move]
    let tripwires: [Tripwire]
    let segments: Segments?
    let plan: Plan?
    let experiments: [Experiment]
    let verdict: Verdict?
}

/// The deep read, made after the hero has drawn.
///
/// Separate from `HealthStore` because the two answer at different speeds: the
/// summary is one small request the Today tab shares; the hub is eleven services
/// and the coach. The tab draws its hero from the first and fills in beneath it
/// from the second, rather than waiting on the slower one for everything.
@MainActor
final class HealthHubStore: ObservableObject {
    @Published private(set) var hub: HubDigest?
    @Published private(set) var loading = false
    @Published private(set) var failed = false

    private let client = SiteClient.shared

    func load(fresh: Bool = false) async {
        guard client.isPaired, !loading else { return }
        loading = true
        defer { loading = false }
        do {
            let payload: HubDigest = try await client.send("api/native/health/hub\(fresh ? "?fresh=1" : "")")
            hub = payload
            failed = false
        } catch {
            // The hero still stands on the summary; the sections below it say
            // they could not load rather than vanishing.
            if hub == nil { failed = true }
        }
    }
}

// MARK: - Heart rate, today

/// The companion's own heart-rate samples, binned by its server
/// (`GET /api/apple/timeline`) — the same read the web movement map draws.
///
/// Binned THERE, not here: a day is ~800 samples, and a 350-point axis cannot
/// honestly show them. Fifteen-minute bins over the last twenty-four hours is
/// 96 points, which it can.
struct HeartTimeline: Decodable {
    struct Series: Decodable {
        let seconds: Int
        /// `[epochSeconds, bpm]` pairs, gaps left out.
        let bins: [[Double]]
    }
    struct Resting: Decodable { let value: Double; let at: String }
    struct Workout: Decodable { let activity: String?; let start: String; let end: String }
    struct Sleep: Decodable { let stage: String?; let start: String; let end: String }

    let from: Int
    let to: Int
    let heartRate: Series
    let restingHeartRate: Resting?
    let workouts: [Workout]
    let sleep: [Sleep]

    struct Point: Identifiable {
        let at: Date
        let bpm: Double
        var id: Date { at }
    }

    var points: [Point] {
        heartRate.bins.compactMap { pair in
            guard pair.count == 2 else { return nil }
            return Point(at: Date(timeIntervalSince1970: pair[0]), bpm: pair[1])
        }
    }
}

@MainActor
final class HeartTimelineStore: ObservableObject {
    @Published private(set) var timeline: HeartTimeline?
    @Published private(set) var loading = false
    @Published private(set) var failed = false

    static let hours = 24
    static let bins = 96

    func load(companion: Companion) async {
        guard !loading else { return }
        // DEBUG only, like every demo path: `SRDemo` does not exist in a
        // Release build, and an unguarded reference fails the TestFlight
        // archive while every Debug CI run stays green.
        #if DEBUG
        if SRDemo.isOn {
            timeline = SRDemoFixtures.heartTimeline(now: Date())
            return
        }
        #endif
        guard companion.paired else { return }
        loading = true
        defer { loading = false }
        let to = Int(Date().timeIntervalSince1970)
        let from = to - Self.hours * 3600
        do {
            timeline = try await companion.api.request("timeline", query: [
                URLQueryItem(name: "from", value: String(from)),
                URLQueryItem(name: "to", value: String(to)),
                URLQueryItem(name: "bins", value: String(Self.bins)),
            ])
            failed = false
        } catch {
            if timeline == nil { failed = true }
        }
    }
}
