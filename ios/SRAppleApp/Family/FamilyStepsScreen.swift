import SwiftUI

/// The keys for Today's optional cards. Off unless the person turns one on —
/// here, in Settings → Today, or with "Show on Today" on the page itself.
enum TodayCards {
    static let steps = "today-card-steps"
    static let tasks = "today-card-tasks"
    /// The travel desk's next moves and flags. ON by default, unlike the two
    /// boards: it draws nothing unless someone has a move due or looks off.
    static let forecast = "today-card-forecast"
}

/// The family step board: your place, the race, everyone ranked.
///
/// The site refreshes the board every fifteen minutes from each person's
/// companion uploads and pushes whoever is knocked off the top; this page is
/// where that push lands. Your own row takes this iPhone's Apple Health count
/// when it is ahead of the board's, and says so ("live").
struct FamilyStepsScreen: View {
    @ObservedObject private var store = FamilyStepsStore.shared
    @AppStorage(TodayCards.steps) private var onToday = false
    @Environment(\.scenePhase) private var scenePhase

    /// Re-read while the page is open: the board moves every fifteen minutes.
    static let refreshInterval: Duration = .seconds(120)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SR.sectionGap) {
                if let board = store.shown {
                    FamilyStepsHero(board: board)
                    if !board.people.isEmpty {
                        ranking(board)
                    }
                    if let line = FamilySteps.yesterdayLine(board) {
                        Label(line, systemImage: "trophy")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkSecondary)
                            .padding(.horizontal, 4)
                            .accessibilityIdentifier("steps-yesterday")
                    }
                } else if store.loaded {
                    SREmpty(
                        title: "No board yet",
                        icon: "figure.walk",
                        message: store.message ?? "Nobody in the family has steps on the board today. It fills in from each phone's Apple Health uploads."
                    )
                } else {
                    ProgressView().tint(SR.accent).frame(maxWidth: .infinity).padding(.top, 80)
                }

                FamilyShowOnToday(isOn: $onToday, what: "your place and the top three")
            }
            .padding(.horizontal, SR.gutter)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .accessibilityIdentifier("family-steps-screen")
        .srGround(.vital)
        .navigationTitle("Steps")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .principal) { SRBarMark() } }
        .srRefreshable { await store.load() }
        .task {
            await store.load()
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.refreshInterval)
                guard !Task.isCancelled else { break }
                await store.load()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await store.load() }
        }
    }

    private func ranking(_ board: FamilyStepsBoard) -> some View {
        let leader = max(board.people.map(\.steps).max() ?? 0, 1)
        return VStack(alignment: .leading, spacing: SR.cardGap) {
            SRSectionLabel(text: "Today", trailing: FamilyStepsFormat.updated(board))
                .padding(.horizontal, 4)
            VStack(spacing: 0) {
                ForEach(Array(board.people.enumerated()), id: \.element.id) { index, person in
                    if index > 0 { Divider().overlay(SR.divider).padding(.leading, 52) }
                    FamilyStepsRow(person: person, leader: leader)
                }
            }
            .padding(.vertical, 4)
            .srGlassCard(.paper)
        }
    }
}

enum FamilyStepsFormat {
    /// "Updated 14:05", from when the site last refreshed the board.
    static func updated(_ board: FamilyStepsBoard) -> String? {
        guard let raw = board.updatedAt, let date = isoDate(raw) else { return nil }
        return "Updated \(date.formatted(date: .omitted, time: .shortened))"
    }
}

/// Your place, big; your steps; the gap to the next person.
struct FamilyStepsHero: View {
    let board: FamilyStepsBoard

    var body: some View {
        SRCard(accented: true) {
            if let mine = board.mine {
                VStack(alignment: .leading, spacing: 8) {
                    SRSectionLabel(text: "Your place", trailing: FamilySteps.tied(board) ? "Joint" : nil)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(FamilySteps.ordinal(mine.rank))
                            .font(SR.Text.hero(56))
                            .foregroundStyle(mine.rank == 1 ? SR.accent : SR.ink)
                        Text("of \(board.people.count)")
                            .font(SR.Text.label(15))
                            .foregroundStyle(SR.inkMuted)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(FamilySteps.figure(mine.steps))
                            .font(SR.Text.figure(30))
                            .foregroundStyle(SR.ink)
                        Text("steps")
                            .font(SR.Text.mono(13))
                            .foregroundStyle(SR.inkMuted)
                        if mine.live {
                            SRGlassChip(text: "Live", icon: "iphone", tone: SR.good)
                                .accessibilityLabel("Live from this iPhone")
                        }
                    }
                    if let gap = FamilySteps.gap(board) {
                        Text(gap)
                            .font(SR.Text.bodyMedium(15))
                            .foregroundStyle(SR.inkSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("steps-hero")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    SRSectionLabel(text: "Your place")
                    Text("You're not on the board yet")
                        .font(SR.Text.display(20))
                        .foregroundStyle(SR.ink)
                    Text("Your steps reach it from this app's Apple Health upload. Turn on Activity in Settings → Apple Health.")
                        .font(SR.Text.secondary())
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// One person on the board: place, name, a bar against the leader, steps.
struct FamilyStepsRow: View {
    let person: FamilyStepsPerson
    let leader: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("\(person.rank)")
                .font(SR.Text.label(15))
                .foregroundStyle(person.rank == 1 ? SR.accent : SR.inkMuted)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(person.me ? "You" : person.name)
                        .font(person.me ? SR.bodyBold(16) : SR.Text.title())
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                    if person.live {
                        Text("LIVE")
                            .font(SR.Text.mono())
                            .tracking(0.8)
                            .foregroundStyle(SR.good)
                    }
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(SR.line)
                        Capsule()
                            .fill(person.me ? SR.accent : SR.accentInk)
                            .frame(width: max(6, geo.size.width * CGFloat(person.steps) / CGFloat(leader)))
                    }
                }
                .frame(height: 6)
                .accessibilityHidden(true)
            }
            Text(FamilySteps.figure(person.steps))
                .font(SR.Text.figure(19))
                .foregroundStyle(SR.ink)
                .monospacedDigit()
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 10)
        .frame(minHeight: SR.tapTarget + 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(FamilySteps.ordinal(person.rank)), \(person.me ? "you" : person.name), \(FamilySteps.figure(person.steps)) steps\(person.live ? ", live" : "")")
        .accessibilityIdentifier("steps-row-\(person.id)")
    }
}

/// "Show on Today", at the foot of each family page.
struct FamilyShowOnToday: View {
    @Binding var isOn: Bool
    let what: String

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Show on Today")
                    .font(SR.Text.title())
                    .foregroundStyle(SR.ink)
                Text("A card with \(what). On this phone only.")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(SR.accent)
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 12)
        .srGlassCard(.paper)
        .accessibilityIdentifier("show-on-today")
    }
}

/// Today's step card: your place and the top three. One tap to the board.
struct TodayStepsCard: View {
    @ObservedObject private var store = FamilyStepsStore.shared
    let open: () -> Void

    var body: some View {
        Button {
            SRHaptic.tap()
            open()
        } label: {
            SRCard(interactive: true) {
                VStack(alignment: .leading, spacing: 10) {
                    SRSectionLabel(text: "Family steps", trailing: store.shown.flatMap(FamilySteps.place))
                    if let board = store.shown, !board.people.isEmpty {
                        if let mine = board.mine {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(FamilySteps.ordinal(mine.rank))
                                    .font(SR.Text.display(30))
                                    .foregroundStyle(mine.rank == 1 ? SR.accent : SR.ink)
                                Text("\(FamilySteps.figure(mine.steps)) steps")
                                    .font(SR.Text.mono(14))
                                    .foregroundStyle(SR.inkSecondary)
                                if mine.live {
                                    Text("LIVE").font(SR.Text.mono()).foregroundStyle(SR.good)
                                }
                            }
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(FamilySteps.top(board, 3)) { person in
                                HStack(spacing: 8) {
                                    Text("\(person.rank)")
                                        .font(SR.Text.label())
                                        .foregroundStyle(SR.inkMuted)
                                        .frame(width: 18, alignment: .leading)
                                    Text(person.me ? "You" : person.name)
                                        .font(SR.Text.bodyMedium(15))
                                        .foregroundStyle(person.me ? SR.accentDeep : SR.ink)
                                    Spacer(minLength: 8)
                                    Text(FamilySteps.figure(person.steps))
                                        .font(SR.Text.mono(14))
                                        .foregroundStyle(SR.ink)
                                        .monospacedDigit()
                                }
                            }
                        }
                    } else {
                        Text(store.loaded ? (store.message ?? "No steps on the board yet today.") : "Reading the board…")
                            .font(SR.Text.secondary())
                            .foregroundStyle(SR.inkMuted)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens the step board")
        .accessibilityIdentifier("today-steps")
    }
}
