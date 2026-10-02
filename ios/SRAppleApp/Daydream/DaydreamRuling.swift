import SwiftUI

// MARK: - Rulings on a note's claim
//
// A rating says whether you want this KIND of note ("Worth knowing", "Not for
// me"). A ruling says whether this note's CLAIM is true. Two authors write one:
//
//   • a double-check, which re-reads the sources and then tries to prove its
//     own note wrong (SR-Main `red-team.ts`);
//   • you — "It's wrong", with why. Your reason is kept word for word as the
//     lesson the next notes are checked against. "It was right" withdraws one.
//
// Wire (SR-Main, additive — an older server sends none of it):
//
//   Note+detail  "review": { "verdict": holds|wrong|unclear, "by": owner|check,
//                            "reasoning", "lesson"? } | null
//   Report       result.review: { verdict, claim, challenges: [{doubt, finding,
//                            survives}], reasoning, lesson?, overruled? } | null
//   POST api/native/daydream/feedback  { "id", "verdict": wrong|right, "why" } → { "ok": true }

/// What a ruling concluded. Anything this build does not know is `unclear` —
/// never `holds`.
enum DaydreamClaimVerdict: String, Hashable {
    case holds, wrong, unclear

    init(raw: String) { self = DaydreamClaimVerdict(rawValue: raw.lowercased()) ?? .unclear }

    var label: String {
        switch self {
        case .holds: return "It holds up"
        case .wrong: return "It was wrong"
        case .unclear: return "Could not settle it"
        }
    }

    var icon: String {
        switch self {
        case .holds: return "checkmark.seal"
        case .wrong: return "xmark.seal"
        case .unclear: return "questionmark.circle"
        }
    }

    var tone: Color {
        switch self {
        case .holds: return SR.good
        case .wrong: return SR.warn
        case .unclear: return SR.inkMuted
        }
    }
}

/// A ruling on a note, as the detailed feed sends it.
struct DaydreamReview: Decodable, Hashable {
    let verdict: DaydreamClaimVerdict
    /// You, or a double-check.
    let byOwner: Bool
    let reasoning: String
    /// What it learned, when wrong.
    let lesson: String?

    init(verdict: DaydreamClaimVerdict, byOwner: Bool, reasoning: String, lesson: String? = nil) {
        self.verdict = verdict
        self.byOwner = byOwner
        self.reasoning = reasoning
        self.lesson = lesson
    }

    enum CodingKeys: String, CodingKey { case verdict, by, reasoning, lesson }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let raw = c.lenient(String.self, .verdict), !raw.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .verdict, in: c, debugDescription: "a ruling needs a verdict")
        }
        verdict = DaydreamClaimVerdict(raw: raw)
        byOwner = c.lenient(String.self, .by) == "owner"
        reasoning = c.lenient(String.self, .reasoning) ?? ""
        lesson = c.lenient(String.self, .lesson).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// The banner's opening line.
    var headline: String {
        if byOwner { return verdict == .wrong ? "You said this is wrong" : "You said this is right" }
        switch verdict {
        case .holds: return "A double-check found this holds"
        case .wrong: return "A double-check found this wrong"
        case .unclear: return "A double-check could not settle this"
        }
    }
}

/// The verdict at the head of a double-check's report.
struct CommissionReview: Decodable, Hashable {
    struct Challenge: Decodable, Hashable {
        let doubt: String
        let finding: String
        let survives: Bool

        enum CodingKeys: String, CodingKey { case doubt, finding, survives }

        init(doubt: String, finding: String, survives: Bool) {
            self.doubt = doubt
            self.finding = finding
            self.survives = survives
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            guard let doubt = c.lenient(String.self, .doubt), !doubt.isEmpty else {
                throw DecodingError.dataCorruptedError(forKey: .doubt, in: c, debugDescription: "a challenge needs a doubt")
            }
            self.doubt = doubt
            finding = c.lenient(String.self, .finding) ?? ""
            survives = c.lenient(Bool.self, .survives) ?? false
        }
    }

    let verdict: DaydreamClaimVerdict
    let claim: String
    let challenges: [Challenge]
    let reasoning: String
    let lesson: String?
    let overruled: String?

    init(verdict: DaydreamClaimVerdict, claim: String = "", challenges: [Challenge] = [], reasoning: String,
         lesson: String? = nil, overruled: String? = nil) {
        self.verdict = verdict
        self.claim = claim
        self.challenges = challenges
        self.reasoning = reasoning
        self.lesson = lesson
        self.overruled = overruled
    }

    enum CodingKeys: String, CodingKey { case verdict, claim, challenges, reasoning, lesson, overruled }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let raw = c.lenient(String.self, .verdict), !raw.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .verdict, in: c, debugDescription: "a review needs a verdict")
        }
        verdict = DaydreamClaimVerdict(raw: raw)
        claim = c.lenient(String.self, .claim) ?? ""
        challenges = c.lossy(Challenge.self, .challenges)
        reasoning = c.lenient(String.self, .reasoning) ?? ""
        lesson = c.lenient(String.self, .lesson).flatMap { $0.isEmpty ? nil : $0 }
        overruled = c.lenient(String.self, .overruled).flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// Your ruling, as you give it.
enum DaydreamOwnerRuling: String, Encodable, Identifiable {
    case wrong, right
    var id: String { rawValue }
}

/// The body of a ruling on `POST api/native/daydream/feedback`.
struct DaydreamRulingRequest: Encodable, Equatable {
    let id: String
    let verdict: DaydreamOwnerRuling
    let why: String
}

/// The fewest characters a "wrong" needs — the site refuses fewer, because the
/// reason is the whole of what it learns from.
let daydreamMinimumWhy = 3

// MARK: - The store

/// Rulings given on this phone, over whatever the note arrived with.
@MainActor
final class DaydreamRulings: ObservableObject {
    static let shared = DaydreamRulings()

    @Published private(set) var given: [String: DaydreamReview] = [:]
    @Published private(set) var sending: Set<String> = []
    @Published private(set) var failed: Set<String> = []

    private let client = SiteClient.shared

    func review(for note: DaydreamNote) -> DaydreamReview? {
        given[note.id] ?? note.review
    }

    /// A ruling you gave here that the note as read does not carry yet.
    func ruledHere(_ note: DaydreamNote) -> Bool {
        guard let mine = given[note.id] else { return false }
        return mine != note.review
    }

    func isSending(_ note: DaydreamNote) -> Bool { sending.contains(note.id) }
    func didFail(_ note: DaydreamNote) -> Bool { failed.contains(note.id) }

    /// Send a ruling. True once the site has kept it.
    @discardableResult
    func record(_ ruling: DaydreamOwnerRuling, why raw: String, for note: DaydreamNote) async -> Bool {
        let why = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if ruling == .wrong, why.count < daydreamMinimumWhy { return false }
        guard !sending.contains(note.id) else { return false }
        sending.insert(note.id)
        failed.remove(note.id)
        defer { sending.remove(note.id) }
        do {
            let body = try JSONEncoder().encode(DaydreamRulingRequest(id: note.id, verdict: ruling, why: why))
            let reply = try await client.post("api/native/daydream/feedback", body: body)
            if let answer = try? JSONDecoder().decode(Reply.self, from: reply), answer.ok == false {
                throw SiteError.message(answer.error ?? "The site did not keep that.")
            }
        } catch {
            failed.insert(note.id)
            return false
        }
        given[note.id] = DaydreamReview(
            verdict: ruling == .wrong ? .wrong : .holds,
            byOwner: true,
            reasoning: why,
            lesson: ruling == .wrong ? why : nil
        )
        return true
    }

    private struct Reply: Decodable { let ok: Bool?; let error: String? }
}

// MARK: - Views

/// The ruling on a note, inside its card: who ruled, why, the lesson kept —
/// and the way to argue with it.
struct DaydreamReviewBanner: View {
    let review: DaydreamReview
    let onRule: (DaydreamOwnerRuling) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: review.verdict.icon)
                    .font(.system(size: 13, weight: .semibold))
                    .accessibilityHidden(true)
                Text(review.headline)
                    .font(SR.Text.bodyMedium(15))
            }
            .foregroundStyle(review.verdict == .unclear ? SR.ink : review.verdict.tone)
            // Your own "wrong" IS the lesson; saying it twice is noise.
            if !review.reasoning.isEmpty, !(review.byOwner && review.verdict == .wrong) {
                Text(review.reasoning)
                    .font(SR.Text.secondary(14))
                    .foregroundStyle(SR.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let lesson = review.lesson {
                Text("Lesson kept: “\(lesson)”")
                    .font(SR.Text.body(14))
                    .foregroundStyle(SR.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("daydream-review-lesson")
            }
            Button {
                SRHaptic.tap()
                onRule(review.verdict == .wrong ? .right : .wrong)
            } label: {
                Text(argueTitle.uppercased())
                    .font(SR.Text.label(12))
                    .tracking(1.1)
                    .foregroundStyle(SR.accentInk)
                    .frame(minHeight: SR.tapTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("daydream-review-argue")
        }
        .padding(.vertical, 10)
        .padding(.leading, 14)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(review.verdict.tone.opacity(0.08))
        .overlay(alignment: .leading) {
            Rectangle().fill(review.verdict.tone).frame(width: 3)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("daydream-review")
    }

    private var argueTitle: String {
        guard review.verdict == .wrong else { return "It's wrong — say why" }
        return review.byOwner ? "Take that back" : "Actually, it was right"
    }
}

/// "Why is it wrong?" — the reason becomes the lesson. For "right", the
/// reason is optional and the earlier lesson is withdrawn.
struct DaydreamRulingSheet: View {
    let note: DaydreamNote
    let ruling: DaydreamOwnerRuling
    @ObservedObject private var rulings = DaydreamRulings.shared
    @Environment(\.dismiss) private var dismiss
    @State private var why = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(note.title)
                        .font(SR.Text.bodyMedium(15))
                        .foregroundStyle(SR.ink)
                        .fixedSize(horizontal: false, vertical: true)
                } header: {
                    SRSectionLabel(text: "The note")
                }
                .srGlassRow()
                Section {
                    TextEditor(text: $why)
                        .font(SR.Text.body())
                        .frame(minHeight: 120)
                        .accessibilityIdentifier("daydream-ruling-why")
                } header: {
                    SRSectionLabel(text: ruling == .wrong ? "Why is it wrong?" : "Why was it right? (optional)")
                } footer: {
                    Text(ruling == .wrong
                         ? "jkai keeps your words as a lesson and checks new notes against it. For example: “one of those is the receipt email for the bank charge, not a second charge.”"
                         : "The earlier lesson is withdrawn, so it stops steering new notes.")
                        .font(SR.Text.secondary(13))
                        .foregroundStyle(SR.inkMuted)
                }
                .srGlassRow()
                if rulings.didFail(note) {
                    Section {
                        Text("Not saved. Try again.")
                            .font(SR.Text.mono())
                            .foregroundStyle(SR.error)
                    }
                    .srGlassRow()
                }
            }
            .srGround(.wire)
            .navigationTitle(ruling == .wrong ? "It's wrong" : "It was right")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if rulings.isSending(note) {
                        ProgressView().tint(SR.accent)
                    } else {
                        Button("Send") { submit() }
                            .disabled(!canSend)
                            .accessibilityIdentifier("daydream-ruling-send")
                    }
                }
            }
        }
    }

    private var canSend: Bool {
        ruling == .right || why.trimmingCharacters(in: .whitespacesAndNewlines).count >= daydreamMinimumWhy
    }

    private func submit() {
        SRHaptic.tap()
        let note = self.note
        let ruling = self.ruling
        let why = self.why
        Task {
            if await rulings.record(ruling, why: why, for: note) { dismiss() }
        }
    }
}
