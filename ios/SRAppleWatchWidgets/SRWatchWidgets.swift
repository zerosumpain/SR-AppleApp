import SwiftUI
import WidgetKit

// Complications and Smart Stack, from the snapshot the Watch app leaves on the
// App Group shelf (`WatchShelf`). No request of their own: the Watch app
// reloads these timelines whenever the phone sends a new snapshot.

struct ShelfEntry: TimelineEntry {
    let date: Date
    let snapshot: WatchSnapshot
}

struct ShelfProvider: TimelineProvider {
    func placeholder(in context: Context) -> ShelfEntry {
        ShelfEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (ShelfEntry) -> Void) {
        completion(ShelfEntry(date: Date(), snapshot: context.isPreview ? .preview : (WatchShelf.load() ?? .empty)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ShelfEntry>) -> Void) {
        let entry = ShelfEntry(date: Date(), snapshot: WatchShelf.load() ?? .empty)
        // The app pushes reloads; this is only the fallback that keeps "how
        // old" honest if the phone goes quiet.
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
    }
}

private let accent = Color(token: SRTokens.Colour.accentOnDark.light)

// MARK: - Readiness

struct ReadinessComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "sr.readiness", provider: ShelfProvider()) { entry in
            ReadinessView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Readiness")
        .description("Today's readiness score from Strange Ramblings.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline, .accessoryRectangular])
    }
}

struct ReadinessView: View {
    let entry: ShelfEntry
    @Environment(\.widgetFamily) private var family

    private var readiness: WatchSnapshot.Figure? { entry.snapshot.readiness }
    private var score: String { readiness?.display ?? "—" }

    var body: some View {
        switch family {
        case .accessoryCircular:
            Gauge(value: readiness?.fraction ?? 0) {
                Text("READY")
            } currentValueLabel: {
                Text(score)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .tint(accent)
            .widgetAccentable()
        case .accessoryCorner:
            Text(score)
                .font(.title3)
                .widgetCurvesContent()
                .widgetLabel {
                    Gauge(value: readiness?.fraction ?? 0) { Text("Readiness") }
                        .tint(accent)
                }
        case .accessoryInline:
            Text(readiness.map { "Readiness \($0.display) · \($0.label)" } ?? "Readiness —")
        default:
            VStack(alignment: .leading, spacing: 2) {
                Text("READINESS").font(.caption2).foregroundStyle(accent).widgetAccentable()
                Text(readiness.map { "\($0.display) · \($0.label)" } ?? "Not in yet")
                    .font(.headline)
                    .lineLimit(1)
                if let recovery = entry.snapshot.recovery {
                    Text("Recovery \(recovery.display)%").font(.caption).lineLimit(1)
                }
                if entry.snapshot.unread > 0 {
                    Text("\(entry.snapshot.unread) unread").font(.caption2).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Unread

struct UnreadComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "sr.unread", provider: ShelfProvider()) { entry in
            UnreadView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Alerts")
        .description("Unread alerts from the site.")
        .supportedFamilies([.accessoryCircular, .accessoryInline])
    }
}

struct UnreadView: View {
    let entry: ShelfEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryInline:
            Text(entry.snapshot.unread == 0 ? "No unread alerts" : "\(entry.snapshot.unread) unread alerts")
        default:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: entry.snapshot.unread > 0 ? "bell.badge.fill" : "bell")
                        .font(.caption)
                        .widgetAccentable()
                    Text("\(entry.snapshot.unread)").font(.headline)
                }
            }
        }
    }
}

@main
struct SRWatchWidgets: WidgetBundle {
    var body: some Widget {
        ReadinessComplication()
        UnreadComplication()
    }
}

extension WatchSnapshot {
    /// The gallery's sample, never shown as a reading.
    static let preview = WatchSnapshot(
        generatedAt: Date(),
        readiness: Figure(key: "readiness", label: "Primed", display: "72", unit: nil, fraction: 0.72),
        recovery: Figure(key: "recovery", label: "Recovery", display: "68", unit: "%", fraction: 0.68),
        figures: [], healthUpdatedAt: nil, alerts: [], unread: 2, showsAlerts: true,
        sync: Sync(queued: 0, lastUpload: nil, gate: nil), connectionNeedsFixing: false,
        pinnedFlows: [], canAsk: false
    )
}
