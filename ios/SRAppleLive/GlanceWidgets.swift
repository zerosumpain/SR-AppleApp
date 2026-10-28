import SwiftUI
import WidgetKit

// The glance widgets: what is inside the app, on the Home Screen and the
// Lock Screen — who is home and who is out ("Family now"), the trip day's
// next stop or the next trip ("Trips"), invites and your move ("Games"),
// and today's rings and steps ("Health today").
//
// Each draws the snapshot the app left on the shared Keychain shelf
// (`FamilyShelf`, see `FamilyWidgetShared.swift` for why a Keychain group
// and not an App Group); the app reloads a widget only when its snapshot
// changed. Only Games reads anything for itself — the lobby, every half
// hour, with the site credential the app leaves for the family widgets —
// because an invite can arrive while the app is shut. Family now's view
// comes over the companion pairing, whose credential never leaves the app;
// Trips and Health are worked out on the phone; and this extension never
// reads Apple Health. Their timelines say when the face changes on its own
// (a planned arrival, a lapsing invite, midnight) and read nothing new.
//
// Nested in its own bundle: a `WidgetBundle` body takes ten at most, and the
// main one (`SRLiveBundle`) is near that already.

struct SRGlanceWidgets: WidgetBundle {
    var body: some Widget {
        FamilyNowWidget()
        TripsGlanceWidget()
        GamesGlanceWidget()
        HealthGlanceWidget()
    }
}

/// A widget slot as the shared faces name it.
enum GlanceSlot {
    static func of(_ family: WidgetFamily) -> FamilyMessagesWidgetSize {
        switch family {
        case .systemMedium: return .medium
        case .systemLarge, .systemExtraLarge: return .large
        case .accessoryCircular: return .circular
        case .accessoryRectangular: return .rectangular
        case .accessoryInline: return .inline
        default: return .small
        }
    }
}

/// The container background every glance widget wears: the feature's hue on
/// the Home Screen, the system's own on the Lock Screen.
private struct GlanceBackground: ViewModifier {
    let family: WidgetFamily
    let hue: SRHueSpec

    func body(content: Content) -> some View {
        content.containerBackground(for: .widget) {
            switch family {
            case .accessoryCircular: AccessoryWidgetBackground()
            case .accessoryRectangular, .accessoryInline: Color.clear
            default: FamilyWidgetGround(hue: hue)
            }
        }
    }
}

// MARK: - Family now

struct FamilyNowEntry: TimelineEntry {
    let date: Date
    let snapshot: FamilyNowSnapshot?
    var palette: SRWidgetPalette = .load()
}

struct FamilyNowProvider: TimelineProvider {
    /// How often "5m" beside a name moves on: no fetch, only the clock.
    private static let tick: TimeInterval = 10 * 60
    /// Then the shelf is read again, in case the app left a newer view.
    private static let span: TimeInterval = 60 * 60

    func placeholder(in context: Context) -> FamilyNowEntry {
        FamilyNowEntry(date: Date(), snapshot: FamilyNowWidgetSamples.snapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (FamilyNowEntry) -> Void) {
        let saved = Self.saved()
        completion(FamilyNowEntry(date: Date(), snapshot: saved ?? (context.isPreview ? FamilyNowWidgetSamples.snapshot() : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FamilyNowEntry>) -> Void) {
        let snapshot = Self.saved()
        let now = Date()
        let entries = (0..<Int(Self.span / Self.tick)).map {
            FamilyNowEntry(date: now.addingTimeInterval(Double($0) * Self.tick), snapshot: snapshot)
        }
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(Self.span))))
    }

    /// Nothing without the family credential: a phone that left the family
    /// shows no family.
    private static func saved() -> FamilyNowSnapshot? {
        guard FamilyShelf.read(.credential) != nil else { return nil }
        return FamilyShelf.load(FamilyNowSnapshot.self, .familyNow)
    }
}

struct FamilyNowWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: FamilyWidgetKind.familyNow, provider: FamilyNowProvider()) { entry in
            FamilyNowEntryView(entry: entry).privacySensitive()
        }
        .configurationDisplayName("Family now")
        .description("Who's home, who's out and who's on the move, with their battery.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct FamilyNowEntryView: View {
    let entry: FamilyNowEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        FamilyNowWidgetView(snapshot: entry.snapshot, size: GlanceSlot.of(family), now: entry.date, palette: entry.palette)
            .modifier(GlanceBackground(family: family, hue: entry.palette.family))
            .widgetURL(GlanceLink.familyURL)
    }
}

// MARK: - Trips

struct TripsGlanceEntry: TimelineEntry {
    let date: Date
    let snapshot: TripsWidgetSnapshot?
    var palette: SRWidgetPalette = .load()
}

struct TripsGlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> TripsGlanceEntry {
        TripsGlanceEntry(date: Date(), snapshot: TripsWidgetSamples.running())
    }

    func getSnapshot(in context: Context, completion: @escaping (TripsGlanceEntry) -> Void) {
        let saved = Self.saved()
        completion(TripsGlanceEntry(date: Date(), snapshot: saved ?? (context.isPreview ? TripsWidgetSamples.running() : nil)))
    }

    /// An entry wherever the face changes on its own — a planned departure
    /// or arrival, the day's end, midnight — then the shelf is read again.
    func getTimeline(in context: Context, completion: @escaping (Timeline<TripsGlanceEntry>) -> Void) {
        let snapshot = Self.saved()
        let entries = TripsWidget.timeline(snapshot, now: Date()).map { TripsGlanceEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private static func saved() -> TripsWidgetSnapshot? {
        guard FamilyShelf.read(.credential) != nil else { return nil }
        return FamilyShelf.load(TripsWidgetSnapshot.self, .trips)
    }
}

struct TripsGlanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: FamilyWidgetKind.trips, provider: TripsGlanceProvider()) { entry in
            TripsGlanceEntryView(entry: entry).privacySensitive()
        }
        .configurationDisplayName("Trips")
        .description("On a trip day, the next stop and when to leave. Otherwise, the countdown to the next trip.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct TripsGlanceEntryView: View {
    let entry: TripsGlanceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        TripsWidgetView(snapshot: entry.snapshot, size: GlanceSlot.of(family), now: entry.date, palette: entry.palette)
            .modifier(GlanceBackground(family: family, hue: entry.palette.trips))
            .widgetURL(TripsWidget.url(entry.snapshot))
    }
}

// MARK: - Games

struct GamesGlanceEntry: TimelineEntry {
    let date: Date
    let snapshot: GamesWidgetSnapshot?
    var palette: SRWidgetPalette = .load()
}

struct GamesGlanceProvider: TimelineProvider {
    /// Invites are pushed, and the app polls while it is open: half an hour
    /// is a catch-up, not the way news arrives.
    private static let refresh: TimeInterval = 30 * 60

    func placeholder(in context: Context) -> GamesGlanceEntry {
        GamesGlanceEntry(date: Date(), snapshot: GamesWidgetSamples.snapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (GamesGlanceEntry) -> Void) {
        let saved = FamilyShelf.read(.credential) == nil ? nil : FamilyShelf.load(GamesWidgetSnapshot.self, .games)
        completion(GamesGlanceEntry(date: Date(), snapshot: saved ?? (context.isPreview ? GamesWidgetSamples.snapshot() : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<GamesGlanceEntry>) -> Void) {
        Task {
            var snapshot = FamilyShelf.load(GamesWidgetSnapshot.self, .games)
            // Only for a person the app has already shown games to: a
            // snapshot on the shelf is the app saying they may play.
            if let saved = snapshot, let fresh = await GamesGlanceFetch.lobby() {
                let made = GamesWidget.snapshot(fresh, titles: saved.titles.merging(Self.carried(saved)) { a, _ in a }, now: Date())
                if !made.sameContent(as: saved) { FamilyShelf.save(made, .games) }
                snapshot = made
            }
            if FamilyShelf.read(.credential) == nil { snapshot = nil }
            let now = Date()
            let entries = GamesWidget.timeline(snapshot, now: now).map { GamesGlanceEntry(date: $0, snapshot: snapshot) }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(Self.refresh))))
        }
    }

    /// The titles of games the snapshot named, kept for a lobby read here
    /// that names them again.
    private static func carried(_ s: GamesWidgetSnapshot) -> [String: String] {
        var out: [String: String] = [:]
        for row in s.invites + s.moves + [s.last].compactMap({ $0 }) { out[row.game] = row.title }
        return out
    }
}

/// The lobby, read with the family widgets' credential. Unlike
/// `FamilyWidgetFetch.get`, a refusal clears only this widget's snapshot: a
/// person who may not play is still family, and the step board's credential
/// is not this widget's to throw away.
enum GamesGlanceFetch {
    static func lobby() async -> GamesWidgetFeed? {
        guard let credential = FamilyShelf.load(FamilyWidgetCredential.self, .credential),
              let origin = URL(string: credential.origin), origin.scheme == "https" else { return nil }
        var request = URLRequest(url: origin.appending(path: "api/native/games"))
        request.timeoutInterval = 15
        request.setValue("Bearer \(credential.token)", forHTTPHeaderField: "Authorization")
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        let session = URLSession(configuration: config)
        defer { session.finishTasksAndInvalidate() }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 401 || http.statusCode == 403 {
            FamilyShelf.write(nil, .games)
            return nil
        }
        guard (200..<300).contains(http.statusCode) else { return nil }
        return try? JSONDecoder().decode(GamesWidgetFeed.self, from: data)
    }
}

struct GamesGlanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: FamilyWidgetKind.games, provider: GamesGlanceProvider()) { entry in
            GamesGlanceEntryView(entry: entry).privacySensitive()
        }
        .configurationDisplayName("Games")
        .description("Invites waiting, games where it's your move, and how the last one ended.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct GamesGlanceEntryView: View {
    let entry: GamesGlanceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        GamesWidgetView(snapshot: entry.snapshot, size: GlanceSlot.of(family), now: entry.date, palette: entry.palette)
            .modifier(GlanceBackground(family: family, hue: entry.palette.gamesHue))
            .widgetURL(GamesWidget.url(entry.snapshot.map { GamesWidget.live($0, now: entry.date) }))
    }
}

// MARK: - Health today

struct HealthGlanceEntry: TimelineEntry {
    let date: Date
    let snapshot: HealthWidgetSnapshot?
    var palette: SRWidgetPalette = .load()
}

struct HealthGlanceProvider: TimelineProvider {
    func placeholder(in context: Context) -> HealthGlanceEntry {
        HealthGlanceEntry(date: Date(), snapshot: HealthWidgetSamples.snapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (HealthGlanceEntry) -> Void) {
        let saved = Self.saved()
        completion(HealthGlanceEntry(date: Date(), snapshot: saved ?? (context.isPreview ? HealthWidgetSamples.snapshot() : nil)))
    }

    /// Now, and midnight — when today's rings stop being today's. The app
    /// reloads it when they move; nothing else changes it.
    func getTimeline(in context: Context, completion: @escaping (Timeline<HealthGlanceEntry>) -> Void) {
        let snapshot = Self.saved()
        let now = Date()
        let entries = [now, HealthWidget.nextMidnight(after: now)].map { HealthGlanceEntry(date: $0, snapshot: snapshot) }
        completion(Timeline(entries: entries, policy: .never))
    }

    private static func saved() -> HealthWidgetSnapshot? {
        guard FamilyShelf.read(.credential) != nil else { return nil }
        return FamilyShelf.load(HealthWidgetSnapshot.self, .health)
    }
}

struct HealthGlanceWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: FamilyWidgetKind.health, provider: HealthGlanceProvider()) { entry in
            HealthGlanceEntryView(entry: entry).privacySensitive()
        }
        .configurationDisplayName("Health today")
        .description("Today's activity rings and steps, as SR last saw them.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct HealthGlanceEntryView: View {
    let entry: HealthGlanceEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        HealthWidgetView(snapshot: entry.snapshot, size: GlanceSlot.of(family), now: entry.date, palette: entry.palette)
            .modifier(GlanceBackground(family: family, hue: entry.palette.healthHue))
            .widgetURL(GlanceLink.healthURL)
    }
}
