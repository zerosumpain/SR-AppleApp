import SwiftUI

// The tiles added when Home's tiles became widgets (John, 2026-10-27: "I want
// to see inside the app … vs just icons"): the bat phone, the day's diary,
// the Travel kit, Captures, Wildmind and Ask jkai, each drawn at whichever
// size the reader chose (`homeTileSize`) and each showing what is inside it.
//
// The rules they keep are the ones in `HomeTiles.swift`: each observes its own
// store, has a fixed height the grid gives it, and draws something on its
// first frame.

/// The size the grid is drawing a tile at. Nil outside the grid (a preview,
/// a tile in a sheet): a tile then draws its default.
private struct HomeTileSizeKey: EnvironmentKey {
    static let defaultValue: HomeSize? = nil
}

extension EnvironmentValues {
    var homeTileSize: HomeSize? {
        get { self[HomeTileSizeKey.self] }
        set { self[HomeTileSizeKey.self] = newValue }
    }
}

// MARK: - Bat phone

/// The bat phone, as a tile of its own (John, 2026-10-27: "its own addable
/// button" — and it only messages the group). Always on a family phone's
/// Home. The button is msg family's own `BatPhoneButton`, with its guard: the
/// first tap arms it, the second sends.
///
/// The tile itself opens msg family, where the message lands; the button
/// inside it is a target of its own.
struct HomeBatPhoneTile: View {
    @Environment(\.homeTileSize) private var size

    var body: some View {
        if size == .square {
            HomeTileFrame(kind: .batPhone) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Need the family?")
                        .font(SR.Text.title(16))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("Tap twice to message everyone at once.")
                        .font(SR.Text.secondary(13))
                        .opacity(0.9)
                        .lineLimit(3)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    BatPhoneButton()
                        .fixedSize()
                }
            }
        } else {
            let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
            HStack(spacing: 10) {
                Image(systemName: HomeTileKind.batPhone.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(HomeTileKind.batPhone.hue.onFill)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(HomeTileKind.batPhone.hue.gradient))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(HomeTileKind.batPhone.title)
                        .font(SR.Text.title(15))
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text("Tap twice to message the family")
                        .font(SR.Text.secondary(12))
                        .foregroundStyle(SR.inkMuted)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                }
                .accessibilityElement(children: .combine)
                Spacer(minLength: 4)
                BatPhoneButton()
                    .fixedSize()
            }
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background { Color.clear.srGlass(.paper, in: shape) }
            .clipShape(shape)
            .overlay(shape.strokeBorder(.white.opacity(0.5), lineWidth: 1))
            .shadow(color: SR.ink.opacity(0.06), radius: 10, y: 4)
            .contentShape(shape)
        }
    }
}

// MARK: - Today's diary

/// The owner's day: what is left of it, each entry with when it starts and,
/// where the travel desk worked one out, when to leave. A clear day folds the
/// tile to a square that says so and names the next thing; an entry opens it
/// out to 4×2 (`HomeTileKind.adaptive`).
///
/// The diary is the travel desk's (`FamilyForecast.upcoming`): the owner's
/// next two days of events with a place, with the reader's own corrections
/// applied, exactly as Family's "Coming up" shows them.
struct HomeDiaryTile: View {
    @ObservedObject private var forecast = FamilyForecastStore.shared
    @ObservedObject private var corrections = JourneyCorrections.shared
    @Environment(\.homeTileSize) private var size
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        // Once a minute: "In 25 min" must not sit still.
        TimelineView(.periodic(from: .now, by: 60)) { context in
            let now = context.date
            let agenda = Self.agenda(forecast: forecast.forecast, corrections: corrections, now: now)
            HomeTileFrame(kind: .diary, badge: badgeText(agenda)) {
                if let agenda, agenda.hasContent, size != .square {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(agenda.today.prefix(typeSize >= .xxLarge ? 2 : 3)) { entry in
                            row(entry, now: now)
                        }
                        Spacer(minLength: 0)
                    }
                } else if let agenda, agenda.hasContent, let first = agenda.today.first {
                    VStack(alignment: .leading, spacing: 4) {
                        Spacer(minLength: 0)
                        HomeFigure(value: HomeDiary.when(first, now: now, zone: .current), caption: first.title, size: 24, captionLines: 2)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Spacer(minLength: 0)
                        HomeFigure(value: agenda?.readable == false ? "Unread" : "Clear",
                                   caption: quietLine(agenda), size: 26, captionLines: 2)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(agenda, now: now))
        }
    }

    /// Nil until the desk has answered once; then what is left of today. PURE
    /// over its inputs, and what Home sizes the tile by.
    @MainActor
    static func agenda(forecast: FamilyForecast?, corrections: JourneyCorrections, now: Date) -> HomeDiary.Agenda? {
        guard let forecast else { return nil }
        guard let upcoming = corrections.apply(forecast.upcoming) else {
            return HomeDiary.Agenda(today: [], next: nil, readable: true)
        }
        let entries = upcoming.items.compactMap { item -> HomeDiary.Entry? in
            guard let start = parseTimestamp(item.start) else { return nil }
            return HomeDiary.Entry(id: item.id, title: item.title, start: start, end: item.end.flatMap(parseTimestamp),
                                   place: item.place.isEmpty ? nil : item.place, leaveBy: item.leaveBy.flatMap(parseTimestamp))
        }
        return HomeDiary.agenda(entries, now: now, zone: .current, readable: upcoming.available)
    }

    private func row(_ entry: HomeDiary.Entry, now: Date) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(HomeDiary.when(entry, now: now, zone: .current))
                .font(SR.Text.figure(16))
                .lineLimit(1)
                .fixedSize()
            VStack(alignment: .leading, spacing: 0) {
                Text(entry.title)
                    .font(SR.Text.title(14))
                    .lineLimit(1)
                if let line = detail(entry, now: now) {
                    Text(line)
                        .font(SR.Text.secondary(12))
                        .opacity(0.9)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// "Leave 13:35 · Durham" — the leave-by while it is still ahead.
    private func detail(_ entry: HomeDiary.Entry, now: Date) -> String? {
        var parts: [String] = []
        if let leave = entry.leaveBy, leave > now { parts.append("Leave \(HomeBriefing.clock(leave, .current))") }
        if let place = entry.place { parts.append(place) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func badgeText(_ agenda: HomeDiary.Agenda?) -> String? {
        guard let agenda, agenda.hasContent else { return nil }
        return agenda.today.count == 1 ? "1 LEFT" : "\(agenda.today.count) LEFT"
    }

    private func quietLine(_ agenda: HomeDiary.Agenda?) -> String {
        guard let agenda else { return "Reading the diary…" }
        if !agenda.readable { return "The diary could not be read just now" }
        guard let next = agenda.next else { return "Nothing else today" }
        return "Next: \(next.title), \(next.start.formatted(.dateTime.weekday(.abbreviated).hour().minute()))"
    }

    private func spoken(_ agenda: HomeDiary.Agenda?, now: Date) -> String {
        guard let agenda else { return "Today's diary. Reading it" }
        guard agenda.hasContent else { return "Today's diary. " + quietLine(agenda) }
        return "Today's diary. " + agenda.today.prefix(3).map { entry in
            "\(entry.title), \(HomeDiary.when(entry, now: now, zone: .current))" + (detail(entry, now: now).map { ", \($0)" } ?? "")
        }.joined(separator: ". ")
    }
}

// MARK: - Travel kit

/// The Travel kit's tools as four doors on a square — translate, read a sign,
/// phrases, money — each straight into its tool. As a shortcut, one line.
struct HomeTravelTile: View {
    let open: (TravelToolRef?) -> Void
    @Environment(\.homeTileSize) private var size

    static let tools: [TravelToolRef] = [.translate, .reader, .phrases, .money]

    var body: some View {
        if size == .square {
            HomeTileFrame(kind: .travel, look: .glass) {
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        door(Self.tools[0])
                        door(Self.tools[1])
                    }
                    GridRow {
                        door(Self.tools[2])
                        door(Self.tools[3])
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .accessibilityElement(children: .contain)
        } else {
            HomeShortcutTile(kind: .travel, line: "Translate, signs, money, the way back")
        }
    }

    private func door(_ tool: TravelToolRef) -> some View {
        Button {
            SRHaptic.tap()
            open(tool)
        } label: {
            Image(systemName: tool.icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(tool.fill.gradient))
        }
        .buttonStyle(SRPressStyle())
        .accessibilityLabel(tool.title)
        .accessibilityIdentifier("home-travel-\(tool.rawValue)")
    }
}

// MARK: - Captures

/// Captures: recording now, waiting to send, or follow-ups to decide — and,
/// on a square, a record button, so a thought can be caught from Home.
struct HomeCapturesTile: View {
    @ObservedObject private var store = CaptureStore.shared
    @ObservedObject private var recorder = CaptureRecorder.shared
    @Environment(\.homeTileSize) private var size

    var body: some View {
        if size == .square {
            HomeTileFrame(kind: .captures, badge: recorder.recording ? "REC" : nil) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(store.items.first?.title ?? "Nothing captured yet")
                        .font(SR.Text.secondary(13))
                        .lineLimit(2)
                        .opacity(0.92)
                    Spacer(minLength: 0)
                    HStack(alignment: .bottom) {
                        Text(status ?? "Ready")
                            .font(SR.Text.label(13))
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 4)
                        Button {
                            SRHaptic.tap()
                            Task { await recorder.toggle(source: "home") }
                        } label: {
                            Image(systemName: recorder.recording ? "stop.fill" : "mic.fill")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(HomeTileKind.captures.hue.base)
                                .frame(width: 48, height: 48)
                                .background(Circle().fill(HomeTileKind.captures.hue.onFill))
                        }
                        .buttonStyle(SRPressStyle())
                        .accessibilityLabel(recorder.recording ? "Stop recording" : "Record a capture")
                        .accessibilityIdentifier("home-captures-record")
                    }
                }
            }
            .accessibilityElement(children: .contain)
        } else {
            HomeShortcutTile(kind: .captures, line: status ?? "Record a thought or a conversation")
        }
    }

    /// The same words as the Captures door in More.
    private var status: String? {
        if recorder.recording { return "Recording" }
        if !store.queue.isEmpty { return store.queue.count == 1 ? "1 waiting to send" : "\(store.queue.count) waiting to send" }
        let open = store.items.reduce(0) { $0 + $1.actionsOpen }
        return open > 0 ? (open == 1 ? "1 to decide" : "\(open) to decide") : nil
    }
}

// MARK: - Wildmind

/// The valley as it stands: the day of this life, the season and the
/// weather, and what each of the two minds is doing.
struct HomeWildmindTile: View {
    @ObservedObject private var store = WildmindStore.shared
    @Environment(\.homeTileSize) private var size

    var body: some View {
        let snapshot = store.answer?.snapshot
        if size == .square {
            HomeTileFrame(kind: .wildmind, badge: snapshot?.time.day.map { "DAY \($0)" }) {
                VStack(alignment: .leading, spacing: 6) {
                    if let snapshot {
                        ForEach(snapshot.people.prefix(2)) { person in
                            Text("\(person.name) · \(person.alive ? person.doing : "gone")")
                                .font(SR.Text.secondary(13))
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        Spacer(minLength: 0)
                        Text(Self.sky(snapshot.time) ?? "The world it is building")
                            .font(SR.Text.label(13))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .opacity(0.9)
                    } else {
                        Spacer(minLength: 0)
                        HomeFigure(value: "Wildmind", caption: "The world it is building", size: 22)
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken(snapshot))
        } else {
            let words = snapshot.map { s in
                [s.time.day.map { "Day \($0)" }, Self.sky(s.time)].compactMap { $0 }.joined(separator: " · ")
            } ?? ""
            HomeShortcutTile(kind: .wildmind, line: words.isEmpty ? "The world it is building" : words)
        }
    }

    /// "Autumn · rain · 9°".
    static func sky(_ time: WildmindTime) -> String? {
        let parts = [time.season?.capitalized, time.weather, time.tempC.map { "\(Int($0.rounded()))°" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func spoken(_ snapshot: WildmindSnapshot?) -> String {
        guard let snapshot else { return "Wildmind" }
        let day = snapshot.time.day.map { ". Day \($0)" } ?? ""
        let people = snapshot.people.prefix(2).map { "\($0.name) \($0.alive ? $0.doing : "gone")" }.joined(separator: ", ")
        return "Wildmind\(day). \(people)"
    }
}

// MARK: - Ask jkai

/// Ask jkai: as a shortcut, one line; as a square or wide tile, the thread
/// last spoken in — a tap opens Chat — and a button for a new question.
struct HomeChatTile: View {
    let thread: TodayThread?
    let ask: () -> Void
    @Environment(\.homeTileSize) private var size

    var body: some View {
        if size == .compact || size == nil {
            HomeShortcutTile(kind: .chat, line: thread?.title.map { "Last: \($0)" } ?? "Ask anything, any time")
        } else {
            HomeTileFrame(kind: .chat, look: .glass) {
                VStack(alignment: .leading, spacing: 8) {
                    if let thread {
                        Text(thread.title ?? "Untitled thread")
                            .font(SR.Text.title(size == .wide ? 16 : 14))
                            .foregroundStyle(SR.ink)
                            .lineLimit(size == .wide ? 2 : 3)
                        if let at = parseTimestamp(thread.updatedAt) {
                            Text(at, style: .relative)
                                .font(SR.Text.mono(12))
                                .foregroundStyle(SR.inkMuted)
                        }
                    } else {
                        Text("Ask anything, any time")
                            .font(SR.Text.secondary(14))
                            .foregroundStyle(SR.inkSecondary)
                    }
                    Spacer(minLength: 0)
                    Button {
                        SRHaptic.tap()
                        ask()
                    } label: {
                        Label("New question", systemImage: "square.and.pencil")
                            .font(SR.Text.label(13))
                            .foregroundStyle(HomeTileKind.chat.hue.onFill)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(Capsule().fill(HomeTileKind.chat.hue.gradient))
                    }
                    .buttonStyle(SRPressStyle())
                    .accessibilityIdentifier("home-chat-new")
                }
            }
            .accessibilityElement(children: .contain)
        }
    }
}
