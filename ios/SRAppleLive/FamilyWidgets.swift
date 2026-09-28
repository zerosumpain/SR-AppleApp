import SwiftUI
import WidgetKit

// The family's two Home Screen widgets: the step board and the task list.
//
// Each timeline fetches its board with the credential the app left in the
// shared Keychain group (`FamilyShelf`), falls back to the last snapshot the
// app saved, and asks to be refreshed in twenty minutes. The app also reloads
// both whenever it reads a board that changed. See `FamilyWidgetShared.swift`
// for why this is a Keychain group and not an App Group.

private extension FamilyWidgetSize {
    init(_ family: WidgetFamily) {
        switch family {
        case .systemMedium, .systemLarge, .systemExtraLarge: self = .medium
        case .accessoryRectangular, .accessoryInline, .accessoryCircular: self = .rectangular
        default: self = .small
        }
    }
}

// MARK: - Steps

struct FamilyStepsEntry: TimelineEntry {
    let date: Date
    let board: FamilyStepsBoard?
}

struct FamilyStepsProvider: TimelineProvider {
    func placeholder(in context: Context) -> FamilyStepsEntry {
        FamilyStepsEntry(date: Date(), board: FamilyWidgetSamples.steps)
    }

    func getSnapshot(in context: Context, completion: @escaping (FamilyStepsEntry) -> Void) {
        let saved = FamilyShelf.load(FamilyStepsSnapshot.self, .steps)?.board
        completion(FamilyStepsEntry(date: Date(), board: saved ?? (context.isPreview ? FamilyWidgetSamples.steps : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FamilyStepsEntry>) -> Void) {
        Task {
            var board = FamilyShelf.load(FamilyStepsSnapshot.self, .steps)?.board
            if let fresh = await FamilyWidgetFetch.steps() {
                board = fresh
                FamilyShelf.save(FamilyStepsSnapshot(board: fresh, savedAt: Date()), .steps)
            }
            if FamilyShelf.read(.credential) == nil { board = nil }
            let now = Date()
            completion(Timeline(
                entries: [FamilyStepsEntry(date: now, board: board)],
                policy: .after(now.addingTimeInterval(FamilyWidgetTiming.refresh))
            ))
        }
    }
}

struct FamilyStepsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: FamilyWidgetKind.steps, provider: FamilyStepsProvider()) { entry in
            FamilyStepsEntryView(entry: entry).privacySensitive()
        }
        .configurationDisplayName("Family steps")
        .description("Your place on today's family step board.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct FamilyStepsEntryView: View {
    let entry: FamilyStepsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        FamilyStepsWidgetView(board: entry.board, size: FamilyWidgetSize(family), now: entry.date)
            .containerBackground(for: .widget) {
                if family == .accessoryRectangular { Color.clear } else { FamilyWidgetInk.paper }
            }
            .widgetURL(FamilyPage.steps.url)
    }
}

// MARK: - Tasks

struct FamilyTasksEntry: TimelineEntry {
    let date: Date
    let summary: FamilyTasksSummary?
}

struct FamilyTasksProvider: TimelineProvider {
    func placeholder(in context: Context) -> FamilyTasksEntry {
        FamilyTasksEntry(date: Date(), summary: FamilyWidgetSamples.tasks)
    }

    func getSnapshot(in context: Context, completion: @escaping (FamilyTasksEntry) -> Void) {
        let saved = FamilyShelf.load(FamilyTasksSnapshot.self, .tasks)?.summary
        completion(FamilyTasksEntry(date: Date(), summary: saved ?? (context.isPreview ? FamilyWidgetSamples.tasks : nil)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FamilyTasksEntry>) -> Void) {
        Task {
            var summary = FamilyShelf.load(FamilyTasksSnapshot.self, .tasks)?.summary
            if let fresh = await FamilyWidgetFetch.tasks() {
                let made = FamilyTasksSummary.make(fresh)
                summary = made
                FamilyShelf.save(FamilyTasksSnapshot(summary: made, savedAt: Date()), .tasks)
            }
            if FamilyShelf.read(.credential) == nil { summary = nil }
            let now = Date()
            completion(Timeline(
                entries: [FamilyTasksEntry(date: now, summary: summary)],
                policy: .after(now.addingTimeInterval(FamilyWidgetTiming.refresh))
            ))
        }
    }
}

struct FamilyTasksWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: FamilyWidgetKind.tasks, provider: FamilyTasksProvider()) { entry in
            FamilyTasksEntryView(entry: entry).privacySensitive()
        }
        .configurationDisplayName("Family tasks")
        .description("What's left to do, what's waiting on a parent, and what's owed.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular])
    }
}

struct FamilyTasksEntryView: View {
    let entry: FamilyTasksEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        FamilyTasksWidgetView(summary: entry.summary, size: FamilyWidgetSize(family))
            .containerBackground(for: .widget) {
                if family == .accessoryRectangular { Color.clear } else { FamilyWidgetInk.paper }
            }
            .widgetURL(FamilyPage.tasks.url)
    }
}
