import SwiftUI
import WidgetKit

// msg family on the Home Screen and the Lock Screen, and the bat phone's own
// button beside it.
//
// msg family's timeline works as the step board's does (`FamilyWidgets.swift`):
// it reads the feed with the credential the app left on the shelf, falls back
// to the last snapshot the app saved, and asks again in twenty minutes. The
// app saves a snapshot each time msg family loads, and again when it is read,
// so the unread count drops as soon as the thread has been seen
// (`FamilyMessagesWidgetBridge`).
//
// The bat phone's widget sends nothing. A tap opens the app on its check
// (`sr://batphone`, `BatPhoneConfirmSheet`): a widget is the easiest thing on
// a phone to press by accident. A link rather than a `Button(intent:)` on
// purpose: a widget's link opens the app on every iOS this supports, where an
// intent that opens the app from a widget leans on the system choosing the
// app's process to run it. The iOS 18 control has no link to offer, so it
// runs `OpenBatPhoneIntent`, which opens the app on the same check.

extension FamilyWidgetFetch {
    /// msg family's feed, as thinly as the widget reads it.
    static func messages() async -> FamilyMessagesWidgetFeed? {
        await get("api/native/family/messages")
    }
}

private extension FamilyMessagesWidgetSize {
    init(_ family: WidgetFamily) {
        switch family {
        case .systemMedium: self = .medium
        case .systemLarge, .systemExtraLarge: self = .large
        case .accessoryCircular: self = .circular
        case .accessoryRectangular: self = .rectangular
        case .accessoryInline: self = .inline
        default: self = .small
        }
    }
}

// MARK: - msg family

struct FamilyMessagesEntry: TimelineEntry {
    let date: Date
    let snapshot: FamilyMessagesSnapshot?
    var palette: SRWidgetPalette = .load()
}

struct FamilyMessagesProvider: TimelineProvider {
    /// How often the "5m" beside a line moves on between refreshes.
    private static let tick: TimeInterval = 5 * 60

    func placeholder(in context: Context) -> FamilyMessagesEntry {
        FamilyMessagesEntry(date: Date(), snapshot: FamilyMessagesWidgetSamples.snapshot())
    }

    func getSnapshot(in context: Context, completion: @escaping (FamilyMessagesEntry) -> Void) {
        let saved = FamilyShelf.load(FamilyMessagesSnapshot.self, .messages)
        completion(FamilyMessagesEntry(date: Date(), snapshot: saved ?? (context.isPreview ? FamilyMessagesWidgetSamples.snapshot() : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FamilyMessagesEntry>) -> Void) {
        Task {
            var snapshot = FamilyShelf.load(FamilyMessagesSnapshot.self, .messages)
            if let fresh = await FamilyWidgetFetch.messages() {
                // Unread as of the last time msg family was open in the app,
                // which only the app knows: it left that on the shelf.
                let made = FamilyMessagesWidget.snapshot(fresh.messages, readAt: snapshot?.readAt, now: Date())
                if !made.sameContent(as: snapshot) { FamilyShelf.save(made, .messages) }
                snapshot = made
            }
            if FamilyShelf.read(.credential) == nil { snapshot = nil }
            let now = Date()
            // One entry per tick until the next refresh, so "5m" becomes
            // "10m" without another fetch.
            let ticks = Int(FamilyWidgetTiming.refresh / Self.tick)
            let entries = (0..<max(ticks, 1)).map {
                FamilyMessagesEntry(date: now.addingTimeInterval(Double($0) * Self.tick), snapshot: snapshot)
            }
            completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(FamilyWidgetTiming.refresh))))
        }
    }
}

struct FamilyMessagesHomeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: FamilyWidgetKind.messages, provider: FamilyMessagesProvider()) { entry in
            FamilyMessagesEntryView(entry: entry).privacySensitive()
        }
        .configurationDisplayName("msg family")
        .description("The family's latest messages, and what you haven't read yet.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge, .accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct FamilyMessagesEntryView: View {
    let entry: FamilyMessagesEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        FamilyMessagesWidgetView(snapshot: entry.snapshot, size: FamilyMessagesWidgetSize(family), now: entry.date, palette: entry.palette)
            .containerBackground(for: .widget) {
                switch family {
                case .accessoryCircular: AccessoryWidgetBackground()
                case .accessoryRectangular, .accessoryInline: Color.clear
                default: FamilyWidgetGround(hue: entry.palette.family)
                }
            }
            .widgetURL(FamilyPage.messages.url)
    }
}

// MARK: - Bat phone

struct BatPhoneEntry: TimelineEntry {
    let date: Date
    /// Set up with the family: the app has left its credential on the shelf.
    let ready: Bool
    var palette: SRWidgetPalette = .load()
}

/// Nothing to fetch: the button only changes when this phone joins or leaves
/// the family, and the app reloads every family widget when it does
/// (`FamilyWidgetBridge.sync`), or the palette (`reloadAllTimelines`).
struct BatPhoneProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatPhoneEntry {
        BatPhoneEntry(date: Date(), ready: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (BatPhoneEntry) -> Void) {
        completion(BatPhoneEntry(date: Date(), ready: context.isPreview || FamilyShelf.read(.credential) != nil))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BatPhoneEntry>) -> Void) {
        let entry = BatPhoneEntry(date: Date(), ready: FamilyShelf.read(.credential) != nil)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct BatPhoneWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: FamilyWidgetKind.batPhone, provider: BatPhoneProvider()) { entry in
            BatPhoneEntryView(entry: entry)
        }
        .configurationDisplayName("Bat phone")
        .description("The bat phone, one tap away. SR asks before anything is sent to the family.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryRectangular])
    }
}

struct BatPhoneEntryView: View {
    let entry: BatPhoneEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        BatPhoneWidgetView(size: FamilyMessagesWidgetSize(family), ready: entry.ready, palette: entry.palette)
            .containerBackground(for: .widget) {
                switch family {
                case .accessoryCircular: AccessoryWidgetBackground()
                case .accessoryRectangular, .accessoryInline: Color.clear
                default: FamilyWidgetGround(hue: BatPhoneLook.hue(entry.palette))
                }
            }
            .widgetURL(BatPhoneURL.url)
    }
}

/// Control Center, the Lock Screen and the Action Button (iOS 18): the bat
/// phone's check, one press away. It opens the app; it never sends.
@available(iOS 18.0, *)
struct BatPhoneControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.strangeramblings.family.batphone.control") {
            ControlWidgetButton(action: OpenBatPhoneIntent()) {
                Label("Bat phone", systemImage: BatPhoneLook.symbol)
            }
        }
        .displayName("Bat phone")
        .description("Open the bat phone in SR. It asks before anything is sent.")
    }
}
