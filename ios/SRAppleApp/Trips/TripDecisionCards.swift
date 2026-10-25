import SwiftUI

// v8 (2026-10-21): one card system for the planner's decisions, used on
// every screen that has them — the planning home, the day screen's drawer,
// the conversation, the shape pager (plan §5.1):
//
// - `TripQuestionCard` (and `TripQuestionStack`): one line, two to four
//   answers as chips that wrap, You decide, why it is asked, what happens
//   if you skip;
// - `TripProposalCard` (and `TripProposalPager`, `TripCompareView`): what it
//   is and why, its trade-offs, what it pushes out, Preview and Use this,
//   nudges and a "Not this" with a reason;
// - `TripChangesCard` (and `TripChangesToast`): what changed, per day,
//   before → after, with an Undo that says what it undoes.
//
// They read the trip from `TripStore` and act through it, so a card closed
// mid-decision finds the result kept with the trip. What they say comes from
// `TripDecisions` (Foundation, tested).

// MARK: - Questions

/// One quick question, answered with a tap. An editor's tap answers (and the
/// plan re-solves); a member's is a vote on a family question, and a parent
/// decides.
struct TripQuestionCard: View {
    let question: TripQuestion
    let tripId: String
    /// "1 of 3".
    var position: (index: Int, count: Int)? = nil
    /// After an answer that changed the plan.
    var onChange: ((TripChangeRecord) -> Void)? = nil
    @ObservedObject private var store = TripStore.shared
    @State private var failure: String?

    private var bundle: TripBundle? { store.bundles[tripId] }
    private var decides: Bool { TripDecisions.canDecide(bundle?.can ?? .owner) }
    private var zone: TimeZone { TripClock(bundle?.trip.timeZone ?? "UTC").zone }
    private var today: String { TripClock(bundle?.trip.timeZone ?? "UTC").localDate(Date()) }
    private var busy: Bool { store.isBusy(question.id) }
    private var myVote: String? { store.vote(question.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                if let eyebrow = TripDecisions.eyebrow(question, today: today, zone: zone) {
                    Text(eyebrow)
                        .font(SR.Text.label(12))
                        .foregroundStyle(urgent ? TripPalette.overdue : TripPalette.accent)
                }
                Spacer(minLength: 8)
                if let position {
                    Text(TripDecisions.counter(position.index, of: position.count))
                        .font(SR.Text.mono(12))
                        .foregroundStyle(SR.inkMuted)
                }
            }
            Text(question.prompt)
                .font(SR.Text.title(18))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            Label {
                Text(question.why).fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "arrow.triangle.branch").foregroundStyle(TripPalette.accent)
            }
            .font(SR.Text.title(14))
            .foregroundStyle(SR.inkSecondary)
            if let due = TripDecisions.deadline(question, today: today, zone: zone) {
                Label(due.text, systemImage: "calendar.badge.clock")
                    .font(SR.Text.title(13))
                    .foregroundStyle(due.urgent ? TripPalette.overdue : SR.inkSecondary)
            }
            TripFlow(spacing: 8, lineSpacing: 8) {
                ForEach(question.answers) { answer in
                    Button { send(decides ? .answer(answer.id) : .vote(answer.id)) } label: {
                        TripChip(answer.label, icon: myVote == answer.id ? "checkmark" : nil, style: .answer(isDefault: false))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    .accessibilityLabel(TripDecisions.spoken(answer, in: question, voting: !decides))
                }
                if decides {
                    Button { send(.decide) } label: {
                        TripChip("You decide", style: .answer(isDefault: true))
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                    .accessibilityHint("Keeps what the plan assumes now" + (question.defaultAnswer.map { ": \($0.label)" } ?? ""))
                }
            }
            if let votes = TripDecisions.votesLine(question) {
                Text(votes)
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !decides {
                Text(myVote == nil ? "Everyone can vote; a parent decides." : "Your vote is in; a parent decides.")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkMuted)
            }
            if let skip = TripDecisions.ifSkipped(question) {
                Label {
                    Text(skip).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.uturn.forward")
                }
                .font(SR.Text.secondary(14))
                .foregroundStyle(SR.inkMuted)
            }
            if decides || busy || failure != nil {
                HStack {
                    if decides {
                        Button("Skip for now") { send(.skip) }
                            .font(SR.Text.title(15))
                            .foregroundStyle(SR.inkSecondary)
                            .disabled(busy)
                    }
                    Spacer()
                    if busy { ProgressView().controlSize(.small) }
                }
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(TripPalette.overdue)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip.question.card")
    }

    private var urgent: Bool { TripDecisions.deadline(question, today: today, zone: zone)?.urgent ?? false }

    private func send(_ action: QuestionAction) {
        SRHaptic.tap()
        failure = nil
        Task {
            switch await store.answer(question, action, tripId: tripId) {
            case .done(let change):
                SRHaptic.ok()
                if let change { onChange?(change) }
            case .failed(let why):
                SRHaptic.bad()
                failure = why
            case .stale:
                break
            }
        }
    }
}

/// "3 quick questions": the most important on top, the next two peeking
/// under it. Answering one moves the next up; the counter keeps its place.
struct TripQuestionStack: View {
    let questions: [TripQuestion]
    let tripId: String
    var onChange: ((TripChangeRecord) -> Void)? = nil
    /// Answered here this time, so "2 of 3" follows "1 of 3".
    @State private var answeredHere = 0

    var body: some View {
        if let top = questions.first {
            let peeks = min(2, questions.count - 1)
            TripQuestionCard(
                question: top, tripId: tripId,
                position: (answeredHere, answeredHere + questions.count),
                onChange: onChange
            )
            .id(top.id)
            .transition(.asymmetric(insertion: .opacity, removal: .move(edge: .leading).combined(with: .opacity)))
            .padding(.bottom, CGFloat(peeks) * 7)
            .background(alignment: .bottom) {
                ZStack(alignment: .bottom) {
                    if peeks >= 2 { peek.padding(.horizontal, 24) }
                    if peeks >= 1 { peek.padding(.horizontal, 12).padding(.bottom, 7) }
                }
                .accessibilityHidden(true)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: top.id)
            .onChange(of: questions.map(\.id)) { old, new in
                if let gone = old.first, !new.contains(gone) { answeredHere += 1 }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("trip.questions")
        }
    }

    private var peek: some View {
        Color.clear
            .frame(height: 40)
            .srGlassCard(.paper)
    }
}

// MARK: - Proposals

/// One checked alternative: photo with its credit, what and why, the
/// trade-offs, what it pushes out, and two verbs — Preview and Use this.
/// A member sees "Suggest this" instead: they never accept.
struct TripProposalCard: View {
    let proposal: TripProposal
    let tripId: String
    /// "1 of 3" on the photo, in a pager.
    var position: (index: Int, count: Int)? = nil
    /// Given: Preview draws the proposal's day on the map first.
    var onPreview: ((TripProposal) -> Void)? = nil
    var onChange: ((TripChangeRecord) -> Void)? = nil
    @ObservedObject private var store = TripStore.shared
    @State private var stale = false
    @State private var message: String?

    /// The trip's own copy when it has one — a re-checked proposal replaces
    /// the one this card was made with.
    private var current: TripProposal {
        store.bundles[tripId]?.proposals?.first { $0.id == proposal.id } ?? proposal
    }
    private var bundle: TripBundle? { store.bundles[tripId] }
    private var decides: Bool { TripDecisions.canDecide(bundle?.can ?? .owner) }
    private var zone: TimeZone { TripClock(bundle?.trip.timeZone ?? "UTC").zone }
    private var busy: Bool { store.isBusy(current.id) }
    private var outcome: String? { store.decided[current.id] }

    var body: some View {
        let p = current
        let fit = TripDecisions.fitParts(p.tradeoffs.fitText)
        let currency = TripDecisions.currencySymbol(timeZone: bundle?.trip.timeZone ?? "", costText: p.tradeoffs.costText)
        VStack(alignment: .leading, spacing: 9) {
            if let image = p.image {
                TripPhotoView(photo: image, height: 92)
                    .overlay(alignment: .topLeading) { if let position { counter(position) } }
            } else if let position {
                counter(position)
            }
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(p.title)
                    .font(SR.Text.title(19))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 6)
                if let time = fit.time {
                    Text(time).font(SR.Text.mono(12)).foregroundStyle(SR.inkMuted)
                }
            }
            if !p.why.isEmpty {
                Text(p.why)
                    .font(SR.Text.secondary(14))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            TripFlow(spacing: 6, lineSpacing: 6) {
                if let rest = fit.rest {
                    TripChip(rest, icon: "figure.walk", style: p.tradeoffs.fits ? .tradeoff : .warning)
                }
                ForEach(TripDecisions.chips(p, currencySymbol: currency)) { chip in
                    TripChip(chip.text, icon: chip.symbol, style: style(chip))
                }
            }
            .accessibilityElement(children: .combine)
            pushes(p)
            ForEach(TripDecisions.moves(p, zone: zone), id: \.self) { move in
                Label(move, systemImage: "arrow.right.circle")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkSecondary)
            }
            if stale {
                Label("The plan moved on since this was checked. This is the difference now — use it?", systemImage: "arrow.triangle.2.circlepath")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(TripDecisions.summary(p.diff, zone: zone))
                    .font(SR.Text.title(14))
                    .foregroundStyle(SR.inkSecondary)
            }
            if let link = p.evidence.first.flatMap({ s in TripLinkButtons.safeURL(s.url).map { (s, $0) } }) {
                Link(destination: link.1) {
                    Label("Source: " + (link.0.title ?? link.1.host() ?? "the web"), systemImage: "link")
                        .font(SR.Text.mono(12))
                        .lineLimit(1)
                }
            }
            if let outcome {
                Label(outcome, systemImage: "checkmark.circle")
                    .font(SR.Text.title(14))
                    .foregroundStyle(TripPalette.confirmed)
            } else {
                actions(p)
            }
            if let message {
                Text(message)
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip.proposal.card")
    }

    private func counter(_ position: (index: Int, count: Int)) -> some View {
        Text(TripDecisions.counter(position.index, of: position.count))
            .font(SR.Text.label(12))
            .foregroundStyle(Color(hex: 0x15123A))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.86)))
            .padding(8)
    }

    private func style(_ chip: TripDecisions.Chip) -> TripChip.Style {
        switch chip.tone {
        case .warn: return .warning
        case .good: return chip.id == "quiet" ? .highlight : .tradeoff
        case .plain: return .tradeoff
        }
    }

    @ViewBuilder
    private func pushes(_ p: TripProposal) -> some View {
        if let out = TripDecisions.pushesOut(p) {
            Label(out, systemImage: "arrow.uturn.right")
                .font(SR.Text.title(14))
                .foregroundStyle(SR.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if p.kind != .shape {
            Label("Pushes out: nothing", systemImage: "checkmark")
                .font(SR.Text.title(14))
                .foregroundStyle(TripPalette.confirmed)
        }
    }

    @ViewBuilder
    private func actions(_ p: TripProposal) -> some View {
        if decides {
            HStack(spacing: 10) {
                Button { use(p) } label: {
                    if busy { ProgressView().tint(TripPalette.onAccent).frame(maxWidth: .infinity) } else {
                        TripButtonLabel(stale ? "Use it now" : "Use this", fill: true)
                    }
                }
                .tripPrimary()
                .disabled(busy)
                .accessibilityIdentifier("trip.proposal.use")
                if let onPreview, !p.preview.isEmpty {
                    Button { SRHaptic.select(); onPreview(p) } label: {
                        TripButtonLabel("Preview", icon: "eye", fill: true)
                    }
                    .srButton(.regular)
                    .accessibilityHint("Shows it on the map before anything changes")
                    .accessibilityIdentifier("trip.proposal.preview")
                }
            }
        } else if p.place != nil && p.scope.date != nil {
            Button { suggest(p) } label: { TripButtonLabel("Suggest this", icon: "hand.raised", fill: true) }
                .srButton(.regular)
                .disabled(busy)
        }
    }

    private func use(_ p: TripProposal) {
        SRHaptic.tap()
        message = nil
        Task {
            switch await store.accept(p, tripId: tripId) {
            case .done(let change):
                SRHaptic.ok()
                stale = false
                if let change { onChange?(change) }
            case .stale:
                SRHaptic.bad()
                stale = true
            case .failed(let why):
                SRHaptic.bad()
                message = why
            }
        }
    }

    private func suggest(_ p: TripProposal) {
        Task {
            if let failure = await store.suggest(p, tripId: tripId) {
                message = failure
            } else {
                SRHaptic.ok()
                message = "Suggested — a parent will see it."
            }
        }
    }
}

/// A group of alternatives to flick through: its heading and Compare, the
/// cards in a pager (the next one peeking), page dots, and — for an editor —
/// the nudges and "Not this" under the card on show.
struct TripProposalPager: View {
    let group: TripDecisions.ProposalGroup
    let tripId: String
    var onPreview: ((TripProposal) -> Void)? = nil
    var onCompare: ((TripProposal, TripProposal) -> Void)? = nil
    var onChange: ((TripChangeRecord) -> Void)? = nil
    /// A nudge brought a new group: show that one instead.
    var onRegroup: ((String) -> Void)? = nil
    var showsHeading = true
    @ObservedObject private var store = TripStore.shared
    @State private var current: String?
    @State private var message: String?

    private var decides: Bool { TripDecisions.canDecide(store.bundles[tripId]?.can ?? .owner) }
    private var shown: TripProposal? {
        group.proposals.first { $0.id == current } ?? group.proposals.first
    }
    private var index: Int { group.proposals.firstIndex { $0.id == shown?.id } ?? 0 }
    private var nudging: Bool { store.isBusy("nudge:\(group.id)") }

    static let nudges: [Nudge] = [.closer, .cheaper, .lessWalking, .moreLikeThis]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsHeading {
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.heading)
                            .font(SR.Text.title(17))
                            .foregroundStyle(SR.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityAddTraits(.isHeader)
                        Text(subtitle)
                            .font(SR.Text.secondary(13))
                            .foregroundStyle(SR.inkSecondary)
                    }
                    Spacer(minLength: 8)
                    if let onCompare, group.proposals.count >= 2, let a = shown {
                        Button {
                            SRHaptic.tap()
                            let others = group.proposals.filter { $0.id != a.id }
                            let b = index + 1 < group.proposals.count ? group.proposals[index + 1] : others[0]
                            onCompare(a, b)
                        } label: {
                            Label("Compare", systemImage: "rectangle.split.2x1")
                                .font(SR.Text.title(15))
                                .foregroundStyle(TripPalette.accent)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("trip.compare.open")
                    }
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 10) {
                    ForEach(Array(group.proposals.enumerated()), id: \.element.id) { i, p in
                        TripProposalCard(
                            proposal: p, tripId: tripId,
                            position: group.proposals.count > 1 ? (i, group.proposals.count) : nil,
                            onPreview: onPreview, onChange: onChange
                        )
                        .containerRelativeFrame(.horizontal) { width, _ in
                            group.proposals.count > 1 ? max(220, width - 28) : width
                        }
                        .id(p.id)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $current)
            .scrollClipDisabled()
            if group.proposals.count > 1 {
                TripPageDots(count: group.proposals.count, current: index)
                    .frame(maxWidth: .infinity)
            }
            if decides, let p = shown, group.kind != .shape, store.decided[p.id] == nil {
                TripFlow(spacing: 8, lineSpacing: 8) {
                    ForEach(Self.nudges) { nudge in
                        Button { send(nudge, on: p) } label: { TripChip(nudge.label, style: .nudge) }
                            .buttonStyle(.plain)
                            .disabled(nudging)
                            .accessibilityHint("Other ideas like \(p.title), \(nudge.label.lowercased())")
                    }
                    Menu {
                        ForEach(RejectReason.allCases) { reason in
                            Button(reason.label) { reject(p, reason) }
                        }
                    } label: {
                        TripChip("Not this", icon: "hand.thumbsdown", style: .tradeoff)
                    }
                    .accessibilityLabel("Not this: say why")
                }
                if nudging {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Looking again…").font(SR.Text.secondary(13)).foregroundStyle(SR.inkMuted)
                    }
                }
            }
            if let message {
                Text(message)
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(group.kind == .swap ? "trip.swap" : "trip.proposals")
    }

    private var subtitle: String {
        let n = group.proposals.count
        let ideas = n == 1 ? "1 idea, checked" : "\(n) ideas, each checked"
        guard let first = group.proposals.first else { return ideas }
        let zone = TripClock(store.bundles[tripId]?.trip.timeZone ?? "UTC").zone
        let when = [first.scope.date.map { TripFormat.day($0, zone: zone) }, TripDecisions.fitParts(first.tradeoffs.fitText).time]
            .compactMap { $0 }.joined(separator: " ")
        return when.isEmpty ? ideas : "\(when) · \(ideas)"
    }

    private func send(_ nudge: Nudge, on p: TripProposal) {
        SRHaptic.tap()
        message = nil
        Task {
            let (fresh, failure) = await store.nudge(nudge, on: p, tripId: tripId)
            if let failure { message = failure; return }
            if let id = fresh.first?.groupId, id != group.id { onRegroup?(id) }
            current = fresh.first?.id
        }
    }

    private func reject(_ p: TripProposal, _ reason: RejectReason) {
        SRHaptic.select()
        Task {
            if let failure = await store.reject(p, reason: reason, tripId: tripId) { message = failure }
        }
    }
}

/// Two alternatives side by side — the most a phone shows well — with only
/// the rows that differ highlighted, and a tick on the better side where
/// "better" is not a matter of taste.
struct TripCompareView: View {
    let left: TripProposal
    let right: TripProposal
    let tripId: String
    var onChange: ((TripChangeRecord) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = TripStore.shared
    @State private var highlight = true
    @State private var message: String?

    private var bundle: TripBundle? { store.bundles[tripId] }
    private var zone: TimeZone { TripClock(bundle?.trip.timeZone ?? "UTC").zone }
    private var decides: Bool { TripDecisions.canDecide(bundle?.can ?? .owner) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $highlight) {
                    Text("Highlight differences").font(SR.Text.title(16)).foregroundStyle(SR.ink)
                }
                .tint(TripPalette.confirmed)
                .padding(.horizontal, 4)
                HStack(alignment: .top, spacing: 10) {
                    head(left, side: "Left")
                    head(right, side: "Right")
                }
                VStack(spacing: 2) {
                    ForEach(TripDecisions.compare(left, right, zone: zone)) { row in
                        compareRow(row)
                    }
                }
                .padding(6)
                .srGlassCard(.paper)
                Text(footer)
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkSecondary)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                if let message {
                    Text(message).font(SR.Text.secondary(13)).foregroundStyle(TripPalette.overdue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) {
            if decides {
                HStack(spacing: 10) {
                    use(left, "Use left")
                    use(right, "Use right")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
            }
        }
        .srGround(.warm)
        .navigationTitle("Compare")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("trip.compare")
    }

    private func head(_ p: TripProposal, side: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let image = p.image {
                TripPhotoView(photo: image, height: 84, showsCredit: false)
                    .overlay(alignment: .topLeading) { sideLabel(side) }
            } else {
                sideLabel(side)
            }
            Text(p.title)
                .font(SR.Text.title(16))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            if p.tradeoffs.lessVisited {
                TripChip("Less visited", icon: "leaf", style: .highlight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(side): \(p.title)")
    }

    private func sideLabel(_ side: String) -> some View {
        Text(side)
            .font(SR.Text.label(12))
            .foregroundStyle(Color(hex: 0x15123A))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.86)))
            .padding(8)
    }

    private func compareRow(_ row: TripDecisions.CompareRow) -> some View {
        let lit = highlight && row.differs
        let quiet = highlight && !row.differs
        return VStack(spacing: 4) {
            Text(quiet ? "\(row.label) · the same" : row.label)
                .font(SR.Text.label(12))
                .foregroundStyle(SR.inkMuted)
            HStack(alignment: .top, spacing: 10) {
                value(row.left, better: row.better == 0, quiet: quiet)
                value(row.right, better: row.better == 1, quiet: quiet)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 10)
        .background {
            if lit { RoundedRectangle(cornerRadius: SR.Glass.innerRadius, style: .continuous).fill(TripPalette.accentWash) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(row.label): left \(row.left), right \(row.right)" + (row.differs ? "" : ", the same")
                            + (row.better == 0 ? ". Left is better" : row.better == 1 ? ". Right is better" : ""))
    }

    private func value(_ text: String, better: Bool, quiet: Bool) -> some View {
        HStack(spacing: 5) {
            if better {
                Image(systemName: "checkmark").font(SR.Text.label(12)).foregroundStyle(TripPalette.confirmed)
            }
            Text(text)
                .font(SR.Text.title(15))
                .foregroundStyle(quiet ? SR.inkMuted : SR.ink)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }

    private var footer: String {
        guard let date = left.scope.date ?? right.scope.date, let parts = TripClock.components(date) else {
            return "Both are checked against the plan."
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        guard let day = calendar.date(from: parts) else { return "Both are checked against the plan." }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = zone
        f.dateFormat = "EEEE"
        return "Both are checked against \(f.string(from: day))'s plan."
    }

    private func use(_ p: TripProposal, _ title: String) -> some View {
        Button {
            Task {
                switch await store.accept(p, tripId: tripId) {
                case .done(let change):
                    SRHaptic.ok()
                    if let change { onChange?(change) }
                    dismiss()
                case .stale:
                    message = "The plan moved on — go back to see the new difference for \(p.title)."
                case .failed(let why):
                    message = why
                }
            }
        } label: {
            if store.isBusy(p.id) { ProgressView().frame(maxWidth: .infinity) } else { TripButtonLabel(title, fill: true) }
        }
        .srButton(.regular)
        .accessibilityLabel("\(title): \(p.title)")
    }
}

// MARK: - What changed

/// Every answer, swap or re-plan ends here: the day before → after, the
/// walking it adds or saves, and an Undo that says what it undoes.
struct TripChangesCard: View {
    let change: TripChangeRecord
    /// "See Wednesday": open the day.
    var onSeeDay: ((String) -> Void)? = nil
    /// Offer a lasting preference to the planner, in words, to send or not.
    var onRemember: ((String) -> Void)? = nil
    @ObservedObject private var store = TripStore.shared
    @ScaledMetric(relativeTo: .headline) private var badge: CGFloat = 34
    @State private var failure: String?

    private var zone: TimeZone { TripClock(store.bundles[change.tripId]?.trip.timeZone ?? "UTC").zone }

    var body: some View {
        let days = TripDecisions.changeDays(change.diff, zone: zone)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "checkmark")
                    .font(SR.Text.title(15))
                    .foregroundStyle(SR.paper)
                    .frame(width: badge, height: badge)
                    .background(Circle().fill(TripPalette.confirmed))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(TripDecisions.summary(change.diff, zone: zone))
                        .font(SR.Text.title(17))
                        .foregroundStyle(SR.ink)
                    Text(change.title)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Button { SRHaptic.select(); store.dismissChange(change.tripId) } label: {
                    Image(systemName: "xmark")
                        .font(SR.Text.label(13))
                        .foregroundStyle(SR.inkMuted)
                        .frame(minWidth: 32, minHeight: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Put away")
            }
            ForEach(days) { day in
                VStack(alignment: .leading, spacing: 9) {
                    if days.count > 1 {
                        Text(day.title).font(SR.Text.label(12)).foregroundStyle(SR.inkMuted)
                    }
                    ForEach(day.lines) { line in lineRow(line) }
                }
            }
            if let walk = TripDecisions.walkDelta(change.diff.walkDeltaM) {
                Label(walk, systemImage: "figure.walk")
                    .font(SR.Text.title(14))
                    .foregroundStyle(SR.inkSecondary)
            }
            if !change.diff.dropped.isEmpty {
                Label("Left out: " + TripDecisions.list(change.diff.dropped), systemImage: "minus.circle")
                    .font(SR.Text.secondary(13))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let remember = change.remember {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Worth keeping for next time: \(remember)")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if let onRemember {
                        Button { onRemember(remember) } label: { TripButtonLabel("Tell the planner to remember", icon: "bookmark") }
                            .srButton(.regular)
                            .controlSize(.small)
                    }
                }
            }
            HStack(spacing: 12) {
                if change.undoTo != nil {
                    Button { undo() } label: {
                        if store.isBusy("undo:\(change.tripId)") { ProgressView() } else {
                            TripButtonLabel(TripDecisions.undoLabel(change.diff), icon: "arrow.uturn.backward")
                                .lineLimit(1)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    .srButton(.regular)
                    .accessibilityIdentifier("trip.changes.undo")
                }
                Spacer(minLength: 0)
                if let onSeeDay, let date = days.compactMap(\.date).first {
                    Button { onSeeDay(date) } label: {
                        HStack(spacing: 4) {
                            Text("See \(weekday(date))")
                            Image(systemName: "chevron.right").accessibilityHidden(true)
                        }
                        .font(SR.Text.title(15))
                        .foregroundStyle(TripPalette.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let failure {
                Text(failure).font(SR.Text.secondary(13)).foregroundStyle(TripPalette.overdue)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srGlassCard(.paper)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip.changes")
    }

    private func lineRow(_ line: TripDecisions.ChangeLine) -> some View {
        HStack(spacing: 10) {
            Image(systemName: Self.symbol(line.kind))
                .font(SR.Text.label(12))
                .foregroundStyle(TripPalette.accent)
                .frame(width: 28, height: 28)
                .background(Circle().fill(TripPalette.accentWash))
                .accessibilityHidden(true)
            Text(line.title)
                .font(SR.Text.title(15))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 6)
            Self.afterText(line)
                .font(SR.Text.mono(14))
                .foregroundStyle(SR.inkSecondary)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(line.spoken)
    }

    /// "~~15:10~~ → **16:00**", "moves to **Thu 29 Oct 11:45**", "**15:10**".
    static func afterText(_ line: TripDecisions.ChangeLine) -> Text {
        switch line.kind {
        case "retimed":
            let before = line.before.map { Text($0).strikethrough() + Text(" → ") } ?? Text("")
            return before + Text(line.after ?? "").bold()
        case "moved":
            return Text("moves to ") + Text(line.after ?? "").bold()
        case "added":
            return Text(line.after ?? "added").bold()
        case "removed":
            return Text("removed")
        case "dropped":
            return Text(line.after ?? "left out")
        default:
            return Text(line.after ?? "")
        }
    }

    static func symbol(_ kind: String) -> String {
        switch kind {
        case "added": return "plus"
        case "removed": return "minus"
        case "moved": return "arrow.right"
        case "retimed": return "clock"
        case "dropped": return "xmark"
        default: return "circle.fill"
        }
    }

    private func weekday(_ date: String) -> String {
        guard let parts = TripClock.components(date) else { return "the day" }
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        guard let d = c.date(from: parts) else { return "the day" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = zone
        f.dateFormat = "EEEE"
        return f.string(from: d)
    }

    private func undo() {
        SRHaptic.tap()
        failure = nil
        Task {
            if let why = await store.undo(change) { SRHaptic.bad(); failure = why } else { SRHaptic.ok() }
        }
    }
}

/// The same change as a short line over the screen, with Undo: after an
/// answer or a Use this where the full card would cover what changed.
struct TripChangesToast: View {
    let change: TripChangeRecord
    var onOpen: (() -> Void)? = nil
    @ObservedObject private var store = TripStore.shared

    private var zone: TimeZone { TripClock(store.bundles[change.tripId]?.trip.timeZone ?? "UTC").zone }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(TripPalette.confirmed)
                .accessibilityHidden(true)
            Button { onOpen?() } label: {
                VStack(alignment: .leading, spacing: 1) {
                    Text(TripDecisions.summary(change.diff, zone: zone))
                        .font(SR.Text.title(15))
                        .foregroundStyle(SR.ink)
                    Text(change.title)
                        .font(SR.Text.secondary(12))
                        .foregroundStyle(SR.inkSecondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .disabled(onOpen == nil)
            if change.undoTo != nil {
                Button {
                    SRHaptic.tap()
                    Task { _ = await store.undo(change) }
                } label: {
                    if store.isBusy("undo:\(change.tripId)") { ProgressView() } else { TripButtonLabel("Undo", icon: "arrow.uturn.backward") }
                }
                .srButton(.regular)
                .controlSize(.small)
                .accessibilityLabel(TripDecisions.undoLabel(change.diff))
            }
        }
        .padding(.leading, 16)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .srGlass(.paper, in: Capsule())
        .padding(.horizontal, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trip.changes")
    }
}
