import SwiftUI

/// msg family's landing: the family as it is now, under the newest thread and
/// over the box (John, 2026-10-27: "improve the landing screen for family
/// chat — make it more interesting and useful").
///
/// At the foot, not the top: msg family opens at the foot — the thread that
/// moved last sits by the box (2026-10-21) — so the foot is where somebody
/// lands. Above the oldest thread it would only be found by scrolling back
/// through all of them. It scrolls away as the threads are scrolled back.
///
/// Top to bottom:
/// - What you missed: "3 new since 08:10 — Katie, Fintan". A tap goes up to
///   the "New" line.
/// - Who's around: everybody else's circle and where they are. A tap starts a
///   message to them ("@Sam " in the box); a hold offers their page.
/// - The quick lines and the bat phone (`FamilyQuickStrip`). These SEND.
/// - Two or three suggestions for the moment (`FamilyChatSuggestions`). These
///   never send: they fill the box, open the poll sheet written out, or open
///   the thread that is waiting on you.
///
/// The rules are Foundation-only and tested (`FamilyChatSuggestions.swift`);
/// this turns the stores into their plain values and draws the answers.
struct FamilyChatLanding: View {
    /// When msg family was last read, as it stood when the screen opened.
    let since: Date?
    /// Words into the box, after anything already there, keyboard up.
    let fill: (String) -> Void
    let poll: (FamilyPollDraft) -> Void
    let openThread: (String) -> Void
    let openPerson: (String) -> Void
    /// Up to the "New" line. Nil when it is not on the page.
    let jumpToNew: (() -> Void)?

    @ObservedObject private var store = FamilyMessagesStore.shared
    @ObservedObject private var steps = FamilyStepsStore.shared
    @ObservedObject private var forecast = FamilyForecastStore.shared
    /// Their circles grow with the reader's text size, to a point: past it a
    /// circle only pushes the threads off the screen.
    @ScaledMetric(relativeTo: .body) private var circle: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var tile: CGFloat = 70

    var body: some View {
        // Once a minute, so "Home ~17:40" and the time of day's suggestions
        // keep up while the page sits open.
        TimelineView(.everyMinute) { _ in
            if let family = FamilyStore.current {
                FamilyViewReader(store: family) { view in panel(view, now: Date()) }
            } else {
                panel(nil, now: Date())
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("family-landing")
    }

    @ViewBuilder
    private func panel(_ view: HouseholdView?, now: Date) -> some View {
        let people = Self.people(view, forecast: forecast.forecast, now: now)
        let threads = Self.threads(store.thread)
        let missed = FamilyChatNow.missed(threads, since: since, now: now)
        let ideas = FamilyChatSuggestions.make(now: now, people: people, me: store.myName, threads: threads,
                                               steps: walkers(now: now), unreadCount: missed?.count ?? 0,
                                               lastActivity: store.lastActivity)
        VStack(alignment: .leading, spacing: 10) {
            if let missed {
                missedRow(missed)
            }
            VStack(alignment: .leading, spacing: 10) {
                SRSectionLabel(text: "Family now")
                if !people.isEmpty {
                    peopleRow(people, now: now)
                }
                FamilyQuickStrip(identifier: "family-landing-quick")
                if !ideas.isEmpty {
                    ideasRow(ideas)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            // The rows scroll sideways with their clipping off (the quick
            // strip's own choice): cut them at the card's edge, not the screen's.
            .clipShape(RoundedRectangle(cornerRadius: SR.Glass.radius, style: .continuous))
            .srGlassCard(.paper)
        }
        .padding(.top, 6)
    }

    // MARK: - What you missed

    private func missedRow(_ missed: FamilyChatNow.Missed) -> some View {
        Button {
            SRHaptic.select()
            jumpToNew?()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundStyle(SR.accentDeep)
                    .accessibilityHidden(true)
                Text(missed.text)
                    .font(SR.Text.bodyMedium(13))
                    .foregroundStyle(SR.ink)
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(minHeight: 36)
            .background(Capsule().fill(SR.accentDeep.opacity(0.12)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(jumpToNew == nil)
        .accessibilityHint(jumpToNew == nil ? "" : "Goes up to the first new message")
        .accessibilityIdentifier("family-landing-missed")
    }

    // MARK: - Who's around

    private func peopleRow(_ people: [FamilyChatNow.Person], now: Date) -> some View {
        let faces = FamilyFaces()
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 6) {
                ForEach(people, id: \.subject) { person in
                    personTile(person, status: FamilyChatNow.status(person, now: now), faces: faces)
                }
            }
        }
        .scrollClipDisabled()
    }

    private func personTile(_ person: FamilyChatNow.Person, status: FamilyChatNow.Status, faces: FamilyFaces) -> some View {
        Button {
            SRHaptic.select()
            fill("@\(person.name) ")
        } label: {
            VStack(spacing: 2) {
                FamilyFace(subject: person.subject, id: person.subject, name: person.name, size: min(circle, 64), faces: faces)
                    .opacity(status.quiet ? 0.55 : 1)
                    .overlay(alignment: .bottomTrailing) {
                        if let low = status.lowBattery { batteryBadge(low) }
                    }
                    .padding(.bottom, 3)
                Text(person.name)
                    .font(SR.Text.bodyMedium(12))
                    .foregroundStyle(SR.ink)
                Text(status.line)
                    .font(SR.Text.label(11))
                    .foregroundStyle(SR.inkSecondary)
                if let detail = status.detail {
                    Text(detail)
                        .font(SR.Text.label(11))
                        .foregroundStyle(SR.accentDeep)
                }
            }
            .lineLimit(1)
            .frame(width: tile)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                fill("@\(person.name) ")
            } label: {
                Label("Message \(person.name)", systemImage: "at")
            }
            if FamilyChatSuggestions.isOut(person) {
                Button {
                    fill("@\(person.name) what time will you be home?")
                } label: {
                    Label("Ask when they'll be home", systemImage: "house")
                }
            }
            Button {
                openPerson(person.subject)
            } label: {
                Label("\(person.name)'s page", systemImage: "person.crop.circle")
            }
        }
        .accessibilityLabel(status.spoken)
        .accessibilityHint("Starts a message to \(person.name)")
        .accessibilityAction(named: "Open \(person.name)'s page") { openPerson(person.subject) }
        .accessibilityIdentifier("family-landing-person-\(person.subject)")
    }

    /// "18%" in the error colour on the circle's edge: a phone about to go quiet.
    private func batteryBadge(_ pct: Int) -> some View {
        Text("\(pct)%")
            .font(SR.Text.mono(10))
            .foregroundStyle(SR.error)
            .padding(.horizontal, 4)
            .background(Capsule().fill(SR.surface))
            .overlay(Capsule().strokeBorder(SR.error.opacity(0.7), lineWidth: 1))
            .fixedSize()
            .offset(x: 10, y: 3)
            .accessibilityHidden(true)
    }

    // MARK: - Suggestions

    private func ideasRow(_ ideas: [FamilyChatSuggestions.Suggestion]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(ideas) { idea in
                    ideaCard(idea)
                }
            }
        }
        .scrollClipDisabled()
    }

    /// A card, not a capsule like the quick lines over it: those send, these
    /// never do.
    private func ideaCard(_ idea: FamilyChatSuggestions.Suggestion) -> some View {
        Button {
            SRHaptic.select()
            act(idea.action)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: idea.symbol)
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.accentDeep)
                    .frame(minWidth: 20)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(idea.title)
                        .font(SR.Text.bodyMedium(14))
                        .foregroundStyle(SR.ink)
                    Text(idea.reason)
                        .font(SR.Text.secondary(12))
                        .foregroundStyle(SR.inkSecondary)
                }
                .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(SR.accent.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(SR.accent.opacity(0.3), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(idea.title). \(idea.reason)")
        .accessibilityHint(Self.hint(idea.action))
        .accessibilityIdentifier("family-landing-idea-\(idea.id)")
    }

    private func act(_ action: FamilyChatSuggestions.Suggestion.Action) {
        switch action {
        case .fill(let words): fill(words)
        case .poll(let question, let options): poll(FamilyPollDraft(question: question, options: options))
        case .open(let thread): openThread(thread)
        }
    }

    private static func hint(_ action: FamilyChatSuggestions.Suggestion.Action) -> String {
        switch action {
        case .fill: return "Puts this in the box. Nothing is sent until you tap Send."
        case .poll: return "Opens a poll, written out, for you to send"
        case .open: return "Opens the thread"
        }
    }

    // MARK: - From the stores

    /// Today's step board, or nobody: yesterday's leader is old news.
    private func walkers(now: Date) -> [FamilyChatSuggestions.Walker] {
        guard let board = steps.shown, FamilySteps.isToday(board, now: now) else { return [] }
        return board.people.map { FamilyChatSuggestions.Walker(name: FamilyMessagesStore.first($0.name), steps: $0.steps, me: $0.me) }
    }

    /// Everybody but you, from the family view: measured from home by the
    /// Orbit (so "home" means what it means there), with the forecast's
    /// arrival home.
    static func people(_ view: HouseholdView?, forecast: FamilyForecast?, now: Date) -> [FamilyChatNow.Person] {
        guard let view else { return [] }
        let orbit = FamilyOrbitModel.make(view: view, watch: view.watch, now: now)?.people ?? []
        return view.people.filter { !$0.isSelf }.map { person in
            let measured = orbit.first { $0.subject == person.subject }
            return FamilyChatNow.Person(
                subject: person.subject, name: FamilyMessagesStore.first(person.name), status: person.status,
                place: person.placeName, km: measured?.km, atHome: measured?.atHome ?? (person.status == "home"),
                moving: person.moving?.mode, battery: person.batteryPct,
                lastSeen: person.lastSeenAt.flatMap(FamilyPerson.isoDate),
                homeBy: homeBy(person.subject, forecast: forecast, now: now)
            )
        }
    }

    /// When the forecast has somebody arriving home: the middle of the
    /// arrival window of the soonest move home it holds for them.
    static func homeBy(_ subject: String, forecast: FamilyForecast?, now: Date) -> Date? {
        (forecast?.next ?? []).compactMap { move -> Date? in
            guard move.subject == subject, move.to.lowercased() == "home",
                  let from = parseTimestamp(move.arriveFrom), let to = parseTimestamp(move.arriveTo) else { return nil }
            return from.addingTimeInterval(to.timeIntervalSince(from) / 2)
        }
        .filter { $0 > now }
        .min()
    }

    static func threads(_ messages: [FamilyMessage]) -> [FamilyChatSuggestions.Thread] {
        messages.map { message in
            FamilyChatSuggestions.Thread(
                id: message.id, from: FamilyMessagesStore.first(message.fromName), body: message.body,
                at: parseTimestamp(message.at), mine: message.mine,
                replies: message.replies.map { reply in
                    FamilyChatSuggestions.Line(from: FamilyMessagesStore.first(reply.fromName), body: reply.body,
                                               at: parseTimestamp(reply.at), mine: reply.mine)
                }
            )
        }
    }

    /// What the landing reads, fresh as msg family opens: the family view
    /// (a read the companion made seconds ago is reused), the step board, and
    /// the forecast (at most once a minute, by its own clock).
    @MainActor
    static func refresh() async {
        await FamilyStore.current?.load()
        await FamilyStepsStore.shared.load()
        await FamilyForecastStore.shared.load()
    }
}

/// Draws `content` with the family view, and again whenever it changes.
/// `FamilyStore.current` is a plain reference, so something has to observe it.
private struct FamilyViewReader<Content: View>: View {
    @ObservedObject var store: FamilyStore
    @ViewBuilder let content: (HouseholdView?) -> Content

    var body: some View { content(store.view) }
}

/// A person's page from msg family's landing: the Family tab's own page,
/// pushed on whichever stack msg family is on, so Back comes back to the
/// chat. The Family tab re-reads the family every 15 seconds while it is on
/// screen; from Chat nothing else would, so the page does it itself.
struct FamilyChatPersonPage: View {
    let subject: String

    var body: some View {
        if let store = FamilyStore.current {
            FamilyPersonScreen(store: store, subject: subject)
                .task {
                    while !Task.isCancelled {
                        await store.load()
                        await FamilyForecastStore.shared.load()
                        try? await Task.sleep(for: FamilyStore.refreshInterval)
                    }
                }
        } else {
            SREmpty(title: "Not in your family view", icon: "person.crop.circle.badge.questionmark",
                    message: "Open the Family tab to see where everyone is.")
                .frame(maxHeight: .infinity)
                .srGround(.warm)
        }
    }
}
