import SwiftUI

/// The keys for Today's optional cards. Off unless the person turns one on —
/// here, in Settings → Today, or with "Show on Today" on the page itself.
enum TodayCards {
    static let steps = "today-card-steps"
    static let tasks = "today-card-tasks"
}

/// The family step board: your place, the race, everyone ranked.
///
/// The site refreshes the board every fifteen minutes from each person's
/// companion uploads and pushes whoever is knocked off the top; this page is
/// where that push lands. Your own row takes this iPhone's Apple Health count
/// when it is ahead of the board's, and says so ("live").
struct FamilyStepsScreen: View {
    @ObservedObject private var store = FamilyStepsStore.shared
    @ObservedObject private var landgrab = LandgrabStore.shared
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
                    // Yesterday's result, as a note in the margin under the
                    // board rather than a line of the board itself.
                    if let line = FamilySteps.yesterdayLine(board) {
                        Text(line)
                            .font(SR.Text.marginalia(16))
                            .foregroundStyle(SR.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
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

                // Under the ranking. It reads its own endpoint and draws
                // nothing until it has a board, so it can never hold up or
                // break the steps above it.
                LandgrabSection()

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
        .srRefreshable {
            // Not awaited: the pull ends when the step board is back.
            Task { await LandgrabStore.shared.load() }
            await store.load()
        }
        // Its own task, so it runs beside the step board's, never after it.
        .task { await landgrab.load() }
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
            Task { await landgrab.load() }
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
                    // First place is ringed in the orange pen, the way the
                    // site rings the one figure on a page that matters. Any
                    // other place is just written down.
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(FamilySteps.ordinal(mine.rank))
                            .font(SR.Text.hero(56))
                            .tracking(-56 * 0.035)
                            .foregroundStyle(SR.ink)
                            .srInkRing(seed: 31, pad: 10, lineWidth: 2.2, visible: mine.rank == 1)
                            // The ring's room: it reaches 10pt out and about a
                            // sixth of the figure's height above and below.
                            .padding(.leading, mine.rank == 1 ? 10 : 0)
                            .padding(.vertical, mine.rank == 1 ? 4 : 0)
                        Text("of \(board.people.count)")
                            .font(SR.Text.kicker(15))
                            .tracking(SR.Notes.kickerTracking)
                            .foregroundStyle(SR.inkMuted)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(FamilySteps.figure(mine.steps))
                            .font(SR.Text.figure(30))
                            .tracking(-30 * 0.03)
                            .monospacedDigit()
                            .foregroundStyle(SR.ink)
                        Text("STEPS")
                            .font(SR.Text.kicker())
                            .tracking(SR.Notes.kickerTracking)
                            .foregroundStyle(SR.Notes.pen)
                        if mine.live {
                            SRGlassChip(text: "Live", icon: "iphone", tone: SR.good)
                                .accessibilityLabel("Live from this iPhone")
                        }
                    }
                    if let gap = FamilySteps.gap(board) {
                        Text(gap)
                            .font(SR.Text.marginalia(16))
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
                        .tracking(-20 * 0.02)
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
///
/// The leader's figure is double-underlined in the orange pen — the total
/// the board is about. Joint leaders share the line.
struct FamilyStepsRow: View {
    let person: FamilyStepsPerson
    let leader: Int

    var body: some View {
        HStack(spacing: 12) {
            Text("\(person.rank)")
                .font(SR.Text.label(15))
                .foregroundStyle(person.rank == 1 ? SR.Notes.pen : SR.inkMuted)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(person.me ? "You" : person.name)
                        .font(person.me ? SR.bodyBold(16) : SR.Text.title())
                        .foregroundStyle(SR.ink)
                        .lineLimit(1)
                    if person.live {
                        Text("LIVE")
                            .font(SR.Text.kicker())
                            .tracking(SR.Notes.kickerTracking)
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
                .tracking(-19 * 0.03)
                .foregroundStyle(SR.ink)
                .monospacedDigit()
                .modifier(LeaderUnderline(on: person.rank == 1 && person.steps > 0, seed: seedFor(person.id)))
        }
        .padding(.horizontal, SR.cardPadding)
        .padding(.vertical, 10)
        .frame(minHeight: SR.tapTarget + 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(FamilySteps.ordinal(person.rank)), \(person.me ? "you" : person.name), \(FamilySteps.figure(person.steps)) steps\(person.live ? ", live" : "")")
        .accessibilityIdentifier("steps-row-\(person.id)")
    }
}

/// The leader's double underline, or nothing: a modifier so the rows that
/// are not leading carry no empty overlay.
private struct LeaderUnderline: ViewModifier {
    let on: Bool
    let seed: Int

    @ViewBuilder
    func body(content: Content) -> some View {
        if on {
            content.srInkUnderline(seed: seed)
        } else {
            content
        }
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
                    .font(SR.Text.marginalia(14))
                    .foregroundStyle(SR.inkSecondary)
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

/// Today's step card: the top three, in order — nothing else. The kicker sits
/// above the card like Family tracking's, and your own place rides on its
/// right; one tap opens the board. Each line is a contents row: the name,
/// a dotted leader across to the count.
struct TodayStepsCard: View {
    @ObservedObject private var store = FamilyStepsStore.shared
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRSectionLabel(text: "Family steps", trailing: store.shown.flatMap(FamilySteps.place))
            Button {
                SRHaptic.tap()
                open()
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    if let board = store.shown, !board.people.isEmpty {
                        let top = FamilySteps.top(board, 3)
                        ForEach(Array(top.enumerated()), id: \.element.id) { index, person in
                            if index > 0 { Rectangle().fill(SR.divider).frame(height: 1) }
                            // On the baseline, so the leader's dots (which have
                            // no text) sit on the line the words stand on.
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text("\(person.rank)")
                                    .font(SR.Text.label())
                                    .foregroundStyle(SR.inkMuted)
                                    .frame(width: 18, alignment: .leading)
                                Text(person.me ? "You" : person.name)
                                    .font(SR.Text.bodyMedium(15))
                                    .foregroundStyle(person.me ? SR.accentDeep : SR.ink)
                                    .lineLimit(1)
                                    .layoutPriority(1)
                                SRDottedLeader()
                                    .frame(minWidth: 12)
                                Text(FamilySteps.figure(person.steps))
                                    .font(SR.Text.mono(14))
                                    .foregroundStyle(SR.ink)
                                    .monospacedDigit()
                            }
                            .padding(.vertical, 9)
                        }
                    } else {
                        Text(store.loaded ? (store.message ?? "No steps on the board yet today.") : "Reading the board…")
                            .font(SR.Text.marginalia(15))
                            .foregroundStyle(SR.inkSecondary)
                            .padding(.vertical, 9)
                    }
                }
                .padding(.horizontal, SR.cardPadding)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .srGlassCard(.paper, interactive: true)
                .contentShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Opens the step board")
            .accessibilityIdentifier("today-steps")
        }
    }
}
