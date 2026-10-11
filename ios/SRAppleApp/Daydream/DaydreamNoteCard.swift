import SwiftUI

/// One note on the Daydream page, laid out as the decision it asks for:
/// where it came from and how far along it is, what jkai spotted, the step it
/// suggests, what it read — then "What do you want to do?" with three choices,
/// each saying what it leads to.
///
/// Today and the Health tab keep the compact `NoticedNoteRow`; this card is
/// the page's. The accessibility identifiers of the shared answers
/// (`noticed-useful`, `noticed-not-useful`, `noticed-more`, `noticed-title`)
/// are the row's, so the UI tests find the same controls on either.
struct DaydreamNoteCard: View {
    let note: DaydreamNote
    @ObservedObject private var feedback = NoticedFeedback.shared
    @ObservedObject private var commissions = CommissionStore.shared
    @ObservedObject private var store = DaydreamStore.shared
    @ObservedObject private var rulings = DaydreamRulings.shared
    @ObservedObject private var actions = DaydreamActions.shared
    @Environment(\.openURL) private var openURL
    @State private var expanded = false
    /// "Change" reopens the choices over a verdict already given.
    @State private var changing = false
    /// The ruling sheet, while open: "It's wrong" or "It was right".
    @State private var ruling: DaydreamOwnerRuling?

    var body: some View {
        SRCard {
            VStack(alignment: .leading, spacing: 12) {
                kicker
                title
                if !note.summary.isEmpty { summary }
                if !note.replaces.isEmpty { replacesLine }
                if let next = note.next { nextStep(next) }
                if !note.sources.isEmpty { sources }
                if let status = commissionStatus { commissionRow(status) }
                if let act = actions.act(for: note), [.done, .undone, .sent].contains(act.status) {
                    DaydreamActBanner(act: act, busy: actions.isBusy(note)) { run($0) }
                }
                if let message = actions.message[note.id] {
                    Text(message)
                        .font(SR.Text.secondary(14))
                        .foregroundStyle(SR.warn)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("daydream-act-message")
                }
                if let review = rulings.review(for: note) {
                    DaydreamReviewBanner(review: review) { startRuling($0) }
                }
                decision
                if let follow = note.follow, !follow.isEmpty {
                    DaydreamFollowSection(note: note, follow: follow)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("daydream-note-\(note.id)")
        .sheet(item: $ruling) { ruling in
            DaydreamRulingSheet(note: note, ruling: ruling)
        }
        .confirmationDialog(
            "Which calendar should “Do it for me” use?",
            isPresented: Binding(
                get: { actions.choosing?.noteId == note.id },
                set: { if !$0, actions.choosing?.noteId == note.id { actions.choosing = nil } }
            ),
            titleVisibility: .visible
        ) {
            ForEach(actions.choosing?.calendars ?? [], id: \.self) { name in
                Button(name) {
                    let note = self.note
                    Task { await actions.choose(name, thenDo: note) }
                }
            }
            Button("Cancel", role: .cancel) { actions.choosing = nil }
        } message: {
            Text("It asks once, then puts every “Do it for me” entry there.")
        }
    }

    // MARK: - What it is

    private var kicker: some View {
        HStack(spacing: 6) {
            Image(systemName: note.channel.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(SR.accent)
                .accessibilityHidden(true)
            Text(note.channel.label.uppercased())
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(SR.accent)
                .lineLimit(1)
                .layoutPriority(1)
            Text("·")
                .font(SR.Text.label())
                .foregroundStyle(SR.inkGhost)
                .accessibilityHidden(true)
            Text(note.outcome.label.uppercased())
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
            Spacer(minLength: 6)
            DaydreamStageDots(stage: stage)
            Text(shortAgo(note.createdAt))
                .font(SR.Text.mono())
                .foregroundStyle(SR.inkMuted)
                .lineLimit(1)
                .fixedSize()
        }
    }

    private var title: some View {
        Button {
            SRHaptic.tap()
            openURL(link)
        } label: {
            Text(note.title)
                .font(SR.Text.title(17))
                .foregroundStyle(SR.ink)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isHeader)
        .accessibilityHint("Opens the note on the website")
        .accessibilityIdentifier("noticed-title")
    }

    /// "Replaces 2 earlier notes on the same subject: …" — one card per subject.
    private var replacesLine: some View {
        Text("Replaces \(note.replaces.count == 1 ? "an earlier note" : "\(note.replaces.count) earlier notes") on the same subject: \(note.replaces.map(\.title).joined(separator: "; "))")
            .font(SR.Text.secondary(13))
            .foregroundStyle(SR.inkMuted)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("daydream-replaces")
    }

    private var summary: some View {
        Text(note.summary)
            .font(SR.Text.secondary(15))
            .foregroundStyle(SR.inkSecondary)
            .lineSpacing(2)
            .lineLimit(expanded ? nil : 3)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(expanded ? "Shows less" : "Shows all of it")
    }

    private func nextStep(_ next: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("SUGGESTED NEXT STEP")
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(SR.accentInk)
            Text(next)
                .font(SR.Text.body(15))
                .foregroundStyle(SR.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 10)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SR.accentInk.opacity(0.08))
        .overlay(alignment: .leading) {
            Rectangle().fill(SR.accentInk).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("daydream-next-step")
    }

    private var sources: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HOW IT KNOWS")
                .font(SR.Text.label())
                .tracking(1.2)
                .foregroundStyle(SR.inkMuted)
            DaydreamWrap(spacing: 6) {
                ForEach(Array(note.sources.enumerated()), id: \.offset) { _, source in
                    HStack(spacing: 5) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(source)
                            .font(SR.Text.mono())
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(SR.inkSecondary)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Capsule().fill(SR.ink.opacity(0.04)))
                    .overlay(Capsule().strokeBorder(SR.line, lineWidth: 1))
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("How it knows: " + note.sources.joined(separator: "; "))
    }

    // MARK: - A double-check in progress

    private struct Status {
        let id: String?
        let state: String
    }

    /// The live double-check if the store has it, else what the note said.
    private var commissionStatus: Status? {
        if let live = commissions.commission(for: note) { return Status(id: live.id, state: live.state) }
        guard let state = note.commissionState else { return nil }
        return Status(id: note.commissionId, state: state)
    }

    private func commissionRow(_ status: Status) -> some View {
        let tone = DaydreamCommissionStatus.tone(for: status.state)
        return Button {
            SRHaptic.tap()
            if let id = status.id { commissions.destination = CommissionDestination(id: id) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: DaydreamCommissionStatus.icon(for: status.state))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(tone)
                    .frame(width: 20)
                    .accessibilityHidden(true)
                Text("Double-check · \(DaydreamCommission.stateLabel(status.state))")
                    .font(SR.Text.bodyMedium(15))
                    .foregroundStyle(SR.ink)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if status.id != nil {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(SR.inkMuted)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(status.id == nil)
        .accessibilityHint("Opens the sign-off sheet")
        .accessibilityIdentifier("commission-\(status.id ?? note.id)")
    }

    // MARK: - Your call

    @ViewBuilder
    private var decision: some View {
        let current = feedback.verdict(for: note)
        let ruled = rulings.review(for: note).flatMap { $0.byOwner ? $0 : nil }
        VStack(alignment: .leading, spacing: 8) {
            if let current, !changing {
                answered(current)
            } else if let status = actions.act(for: note)?.status, status == .done || status == .sent, !changing {
                answeredDone
            } else if let ruled, !changing {
                answered(ruled)
            } else {
                choices(current)
            }
            if feedback.didFail(note) {
                Text("Not saved. Try again.")
                    .font(SR.Text.mono())
                    .foregroundStyle(SR.error)
            }
        }
        .padding(.top, 2)
    }

    private func choices(_ current: DaydreamVerdict?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text("WHAT DO YOU WANT TO DO?")
                    .font(SR.Text.label())
                    .tracking(1.2)
                    .foregroundStyle(SR.inkMuted)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 6)
                moreMenu
            }
            choice(
                icon: "hand.thumbsup", title: "Worth knowing", detail: "Keep it. More like this.",
                on: current == .useful, id: "noticed-useful"
            ) { send(.useful) }
            if canDoubleCheck {
                choice(
                    icon: "magnifyingglass", title: "Double-check it",
                    detail: "Re-read its sources, then try to prove it wrong. Asks your OK first.",
                    on: false, id: "daydream-double-check"
                ) {
                    SRHaptic.tap()
                    let id = note.id
                    Task { await commissions.prepare(thoughtId: id) }
                }
                .disabled(commissions.busy)
            }
            if let act = actions.act(for: note), act.canDo {
                choice(
                    icon: "arrow.right.circle", title: actions.isBusy(note) ? "Doing it…" : "Do it for me",
                    detail: act.status == .undone ? "Put it back in your diary." : act.label,
                    on: false, id: "daydream-do-it"
                ) { run("do") }
                .disabled(actions.isBusy(note))
            }
            choice(
                icon: "hand.thumbsdown", title: "Not for me", detail: "Fewer like this.",
                on: current == .notUseful, id: "noticed-not-useful"
            ) { send(.notUseful) }
        }
    }

    private func choice(icon: String, title: String, detail: String, on: Bool, id: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: on ? "\(icon).fill" : icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(on ? SR.accent : SR.accentInk)
                    .frame(width: 24, height: 22)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(SR.Text.bodyMedium(16))
                        .foregroundStyle(SR.ink)
                    Text(detail)
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: SR.tapTarget, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(on ? SR.accent.opacity(0.10) : SR.ink.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(on ? SR.accent.opacity(0.5) : SR.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(on ? AccessibilityTraits.isSelected : [])
        .accessibilityIdentifier(id)
    }

    private var moreMenu: some View {
        Menu {
            if rulings.review(for: note)?.verdict != .wrong {
                Button {
                    startRuling(.wrong)
                } label: {
                    Label("It's wrong — say why", systemImage: "xmark.seal")
                }
            }
            Button(role: .destructive) {
                send(.never)
            } label: {
                Label("Never show me this kind", systemImage: "nosign")
            }
            Button {
                openURL(link)
            } label: {
                Label("Open on the website", systemImage: "safari")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(SR.inkMuted)
                .frame(width: SR.tapTarget, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("More")
        .accessibilityIdentifier("noticed-more")
    }

    private func answered(_ verdict: DaydreamVerdict) -> some View {
        HStack(spacing: 10) {
            SRGlassChip(text: Self.label(verdict), icon: Self.icon(verdict), tone: Self.tone(verdict))
                .accessibilityIdentifier("daydream-verdict")
            Spacer(minLength: 6)
            Button {
                SRHaptic.tap()
                withAnimation(.easeInOut(duration: 0.2)) { changing = true }
            } label: {
                SRButtonLabel(title: "Change")
            }
            .srButton()
            .controlSize(.small)
            .accessibilityLabel("Change your answer")
            .accessibilityIdentifier("daydream-change")
        }
    }

    /// Done for you, standing in for a rating.
    private var answeredDone: some View {
        HStack(spacing: 10) {
            SRGlassChip(text: "Done for you", icon: "checkmark.circle", tone: SR.good)
                .accessibilityIdentifier("daydream-verdict")
            Spacer(minLength: 6)
        }
    }

    private func run(_ op: String) {
        SRHaptic.tap()
        let note = self.note
        Task { await actions.run(op, for: note) }
    }

    /// Your ruling on the claim, standing in for a rating.
    private func answered(_ review: DaydreamReview) -> some View {
        HStack(spacing: 10) {
            SRGlassChip(text: review.verdict == .wrong ? "You said it's wrong" : "You said it's right",
                        icon: review.verdict.icon, tone: review.verdict.tone)
                .accessibilityIdentifier("daydream-verdict")
            Spacer(minLength: 6)
            Button {
                SRHaptic.tap()
                withAnimation(.easeInOut(duration: 0.2)) { changing = true }
            } label: {
                SRButtonLabel(title: "Change")
            }
            .srButton()
            .controlSize(.small)
            .accessibilityLabel("Change your answer")
            .accessibilityIdentifier("daydream-change")
        }
    }

    // MARK: - Helpers

    private func startRuling(_ ruling: DaydreamOwnerRuling) {
        SRHaptic.tap()
        self.ruling = ruling
    }

    /// The stage the dots show: the site's, unless something done on this
    /// phone has moved the note on since.
    private var stage: DaydreamStage {
        let bucket = store.bucket(for: note, feedback: feedback, commissions: commissions)
        return bucket == note.bucket ? note.stage : bucket.stage
    }

    /// Offered when the site can re-read the note's sources, double-checks
    /// are switched on, and the note has none yet. An older server that
    /// does not say whether a note is checkable gets the offer, and refuses
    /// it itself if it must — as it did before the key existed.
    private var canDoubleCheck: Bool {
        commissions.enabled && note.checkable != false && commissionStatus == nil
    }

    private func send(_ verdict: DaydreamVerdict) {
        SRHaptic.tap()
        let note = self.note
        withAnimation(.easeInOut(duration: 0.2)) { changing = false }
        Task { await feedback.record(verdict, for: note) }
    }

    static func label(_ verdict: DaydreamVerdict) -> String {
        switch verdict {
        case .useful: return "Worth knowing"
        case .notUseful: return "Not for me"
        case .never: return "Never this kind"
        }
    }

    static func icon(_ verdict: DaydreamVerdict) -> String {
        switch verdict {
        case .useful: return "hand.thumbsup.fill"
        case .notUseful: return "hand.thumbsdown.fill"
        case .never: return "nosign"
        }
    }

    static func tone(_ verdict: DaydreamVerdict) -> Color {
        switch verdict {
        case .useful: return SR.accentInk
        case .notUseful: return SR.accent
        case .never: return SR.inkMuted
        }
    }

    /// The note on the site. A path goes through the paired origin, as every
    /// other site link does; an absolute https address is taken as sent.
    private var link: URL {
        if note.url.hasPrefix("https://"), let absolute = URL(string: note.url) { return absolute }
        return SiteClient.shared.webURL(note.url)
    }
}

// MARK: - Small parts

/// Four dots: where a note is in Spotted → Your call → In motion → Result.
struct DaydreamStageDots: View {
    let stage: DaydreamStage

    var body: some View {
        HStack(spacing: 3) {
            ForEach(DaydreamStage.allCases, id: \.self) { step in
                Circle()
                    .fill(fill(step))
                    .overlay(Circle().strokeBorder(step.number > stage.number ? SR.line : Color.clear, lineWidth: 1))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(stage.number) of 4, \(stage.label)")
        .accessibilityIdentifier("daydream-stage-dots")
    }

    private func fill(_ step: DaydreamStage) -> Color {
        if step == stage { return SR.accent }
        return step.number < stage.number ? SR.accentInk : Color.clear
    }
}

/// How a double-check's state looks wherever it is shown.
enum DaydreamCommissionStatus {
    static func icon(for state: String) -> String {
        switch state {
        case "awaiting_approval", "deferred": return "hand.raised"
        case "queued": return "clock"
        case "running": return "arrow.triangle.2.circlepath"
        case "needs_attention": return "exclamationmark.triangle.fill"
        case "completed": return "doc.text.magnifyingglass"
        case "declined", "cancelled": return "xmark.circle"
        default: return "magnifyingglass"
        }
    }

    static func tone(for state: String) -> Color {
        switch state {
        case "awaiting_approval", "deferred": return SR.accent
        case "needs_attention": return SR.warn
        case "completed": return SR.accentInk
        case "declined", "cancelled": return SR.inkMuted
        default: return SR.accentInk
        }
    }
}

/// Chips that wrap onto as many rows as they need. Also the Family tab's
/// place piles (`FamilyPlaceStacks`).
struct DaydreamWrap: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var row: CGFloat = 0
        var widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: limit.isFinite ? limit : nil, height: nil))
            if x > 0, x + size.width > limit {
                y += row + spacing
                x = 0
                row = 0
            }
            widest = max(widest, x + size.width)
            x += size.width + spacing
            row = max(row, size.height)
        }
        return CGSize(width: limit.isFinite ? limit : widest, height: y + row)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var row: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            if x > bounds.minX, x + size.width > bounds.maxX {
                y += row + spacing
                x = bounds.minX
                row = 0
            }
            view.place(at: CGPoint(x: x, y: y), anchor: .topLeading,
                       proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height))
            x += size.width + spacing
            row = max(row, size.height)
        }
    }
}
