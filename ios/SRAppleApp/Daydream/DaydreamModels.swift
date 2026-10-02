import Foundation

// MARK: - Noticed: the daydream loop's notes
//
// The site's daydream loop writes short, cited NOTES about the owner's life —
// nought to two every 45 minutes, across health, home, mail, chat, diary,
// money and research. The phone shows the latest two on Today and the health
// ones on the Health tab, and sends back a verdict on each so the loop learns
// what is worth saying.
//
// Wire contract (SR-Main, `/api/native/*`, the site credential):
//
//   GET  api/native/today                    → { …, "daydream": { "notes": [Note] } }   (key optional)
//   GET  api/native/daydream?scope=health&limit=5 → { "notes": [Note] }
//   GET  api/native/daydream?detail=1&limit=40   → { "notes": [Note+detail], "pipeline"?, "impact"? }
//        Note+detail adds summary, next, sources, stage, bucket, checkable,
//        commissionId, commissionState, review, act. An older server ignores `detail`;
//        every added key is optional and derived when absent (see
//        `DaydreamNote.split` and `derivedBucket`).
//   POST api/native/daydream/feedback        { "id", "verdict": useful|not_useful|never } → { "ok": true }
//                                            { "id", "verdict": wrong|right, "why" } — a ruling on the claim
//                                            (`DaydreamRuling.swift`)
//
// Everything decodes defensively. The server side is being built in parallel
// with this, and a Today payload that throws is a blank first screen, so an
// unknown outcome is a generic label, a malformed note is dropped on its own,
// and a `daydream` block of the wrong shape is simply no notes.

/// What kind of thing the loop concluded. Drives the small label over a note.
enum DaydreamOutcome: Hashable {
    case correlate, efficiency, qualityOfLife, research, build, healthPlan, suggest, moneyAnalysis
    /// A kind this build does not know yet. Still shown, under a generic label.
    case other(String)

    init(raw: String) {
        switch raw {
        case "correlate": self = .correlate
        case "efficiency": self = .efficiency
        case "quality_of_life": self = .qualityOfLife
        case "research": self = .research
        case "build": self = .build
        case "health_plan": self = .healthPlan
        case "suggest": self = .suggest
        case "money_analysis": self = .moneyAnalysis
        default: self = .other(raw)
        }
    }

    var raw: String {
        switch self {
        case .correlate: return "correlate"
        case .efficiency: return "efficiency"
        case .qualityOfLife: return "quality_of_life"
        case .research: return "research"
        case .build: return "build"
        case .healthPlan: return "health_plan"
        case .suggest: return "suggest"
        case .moneyAnalysis: return "money_analysis"
        case .other(let value): return value
        }
    }

    /// Human wording. The raw keys are the loop's vocabulary, not the reader's.
    var label: String {
        switch self {
        case .correlate: return "A connection"
        case .efficiency: return "Time saver"
        case .qualityOfLife: return "Quality of life"
        case .research: return "Research"
        case .build: return "Build idea"
        case .healthPlan: return "Health plan"
        case .suggest: return "Worth trying"
        case .moneyAnalysis: return "Money"
        case .other: return "Noticed"
        }
    }
}

/// Which part of life the note is about. Drives the glyph beside the label.
enum DaydreamChannel: Hashable {
    case health, home, mail, chat, diary, money, research
    case other(String)

    init(raw: String) {
        switch raw {
        case "health": self = .health
        case "home": self = .home
        case "mail": self = .mail
        case "chat": self = .chat
        case "diary": self = .diary
        case "money": self = .money
        case "research": self = .research
        default: self = .other(raw)
        }
    }

    var icon: String {
        switch self {
        case .health: return "heart"
        case .home: return "house"
        case .mail: return "envelope"
        case .chat: return "bubble.left"
        case .diary: return "book.closed"
        case .money: return "sterlingsign.circle"
        case .research: return "magnifyingglass"
        case .other: return "sparkle"
        }
    }

    /// The area, in words, beside the glyph.
    var label: String {
        switch self {
        case .health: return "Health"
        case .home: return "Home"
        case .mail: return "Mail"
        case .chat: return "Chat"
        case .diary: return "Diary"
        case .money: return "Money"
        case .research: return "Research"
        case .other(let raw):
            let words = raw.replacingOccurrences(of: "_", with: " ").trimmingCharacters(in: .whitespaces)
            return words.isEmpty ? "Mixed" : words.prefix(1).uppercased() + words.dropFirst()
        }
    }
}

/// The reader's answer to a note. `never` means "never show this KIND again"
/// — the loop decides what a kind is; the phone only says so.
enum DaydreamVerdict: String, Codable, Hashable {
    case useful
    case notUseful = "not_useful"
    case never
}

/// Where a note is in the one process the site and the phone both draw:
/// jkai spots something, you make the call, anything approved runs, and a
/// result comes back.
enum DaydreamStage: String, CaseIterable, Hashable {
    case spotted, decide, motion, result

    /// 1-based, for "step 2 of 4".
    var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }

    var label: String {
        switch self {
        case .spotted: return "Spotted"
        case .decide: return "Your call"
        case .motion: return "In motion"
        case .result: return "Result"
        }
    }

    /// The four sentences the onboarding card reads, one a stage. They match
    /// `/jkai/daydreams` word for word.
    var explanation: String {
        switch self {
        case .spotted:
            return "jkai looks at one part of your life at a time and writes down anything worth your attention, citing what it read."
        case .decide:
            return "You decide what it is worth: keep it, have the facts checked again, or tell it this is not for you."
        case .motion:
            return "Anything you approve runs on its own — a fresh check of the sources, or a build idea waiting in the build queue."
        case .result:
            return "The report comes back or the build ships. Your verdicts are the score it learns from."
        }
    }
}

/// Which list a note sits in on the Daydream page.
enum DaydreamBucket: String, CaseIterable, Hashable {
    case decide, motion, done

    /// The stage a bucket stands for, when the server did not name one.
    var stage: DaydreamStage {
        switch self {
        case .decide: return .decide
        case .motion: return .motion
        case .done: return .result
        }
    }
}

struct DaydreamNote: Decodable, Identifiable, Hashable {
    let id: String
    let outcome: DaydreamOutcome
    let channel: DaydreamChannel
    let title: String
    let body: String
    /// ISO-8601, as sent. `shortAgo` reads it.
    let createdAt: String
    /// A site path (`/jkai/daydreams?note=<id>`), opened on the website.
    let url: String
    /// The verdict already recorded on the site, if any.
    let feedback: DaydreamVerdict?

    // `?detail=1` — all optional on the wire, all derived when absent.

    /// The body without its closing "Next:" paragraph.
    let summary: String
    /// The suggested next step, if the note carries one.
    let next: String?
    /// What it read, in words ("Bank spend · last 60 days").
    let sources: [String]
    let stage: DaydreamStage
    let bucket: DaydreamBucket
    /// Whether the site can re-read this note's sources. `nil` is an older
    /// server that did not say; the phone then offers the check and lets
    /// the server refuse, as it did before the key existed.
    let checkable: Bool?
    let commissionId: String?
    let commissionState: String?
    /// The ruling on the note's claim — yours, or a double-check's. `nil`
    /// when there is none, and from an older server.
    let review: DaydreamReview?
    /// "Do it for me" — what it would do, or did. `nil` when the step is not
    /// something it can carry out itself, and from an older server.
    let act: DaydreamAct?
    /// Whether this copy came from the detailed read. A plain copy (Today's
    /// block) must not overwrite what a detailed one knows — see `merged`.
    let detailed: Bool

    init(id: String, outcome: DaydreamOutcome, channel: DaydreamChannel, title: String, body: String,
         createdAt: String, url: String? = nil, feedback: DaydreamVerdict? = nil,
         summary: String? = nil, next: String? = nil, sources: [String] = [],
         stage: DaydreamStage? = nil, bucket: DaydreamBucket? = nil, checkable: Bool? = nil,
         commissionId: String? = nil, commissionState: String? = nil, review: DaydreamReview? = nil,
         act: DaydreamAct? = nil, detailed: Bool = false) {
        self.id = id
        self.outcome = outcome
        self.channel = channel
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.url = url ?? DaydreamNote.defaultPath(for: id)
        self.feedback = feedback
        let split = DaydreamNote.split(body)
        self.summary = summary ?? split.summary
        // nil: derive it from the body. "": the server said there is none.
        if let next { self.next = next.isEmpty ? nil : next } else { self.next = split.next }
        self.sources = sources
        let derived = DaydreamNote.derivedBucket(feedback: feedback, commissionState: commissionState,
                                                 ruled: review?.byOwner == true || act?.status == .done || act?.status == .sent)
        self.bucket = bucket ?? derived
        self.stage = stage ?? (bucket ?? derived).stage
        self.checkable = checkable
        self.commissionId = commissionId
        self.commissionState = commissionState
        self.review = review
        self.act = act
        self.detailed = detailed
    }

    enum CodingKeys: String, CodingKey {
        case id, outcome, channel, title, body, createdAt, url, feedback
        case summary, next, sources, stage, bucket, checkable, commissionId, commissionState, review, act
    }

    /// An id and a title are the note; without either there is nothing to show
    /// or to answer, so the note throws and `Lossy` drops it alone.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = c.flexString(.id), !id.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .id, in: c, debugDescription: "a note needs an id")
        }
        guard let title = c.lenient(String.self, .title), !title.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .title, in: c, debugDescription: "a note needs a title")
        }
        let path = c.lenient(String.self, .url) ?? ""
        let summary = c.lenient(String.self, .summary).flatMap { $0.isEmpty ? nil : $0 }
        let stage = c.lenient(String.self, .stage).flatMap(DaydreamStage.init(rawValue:))
        let bucket = c.lenient(String.self, .bucket).flatMap(DaydreamBucket.init(rawValue:))
        let body = c.lenient(String.self, .body) ?? ""
        let sources = c.lossy(String.self, .sources).filter { !$0.isEmpty }
        let commissionId = c.lenient(String.self, .commissionId).flatMap { $0.isEmpty ? nil : $0 }
        let commissionState = c.lenient(String.self, .commissionState).flatMap { $0.isEmpty ? nil : $0 }
        let detailed = c.contains(.stage) || c.contains(.bucket) || c.contains(.summary)
        self.init(
            id: id,
            outcome: DaydreamOutcome(raw: c.lenient(String.self, .outcome) ?? ""),
            channel: DaydreamChannel(raw: c.lenient(String.self, .channel) ?? ""),
            title: title,
            body: body,
            createdAt: c.lenient(String.self, .createdAt) ?? "",
            url: path.isEmpty ? nil : path,
            // `null`, absent, or a verdict this build does not know — all "not yet".
            feedback: c.lenient(String.self, .feedback).flatMap(DaydreamVerdict.init(rawValue:)),
            summary: summary,
            // A detailed server says what the next step is, even when it is
            // none (`null`); only an older one leaves the body to be split.
            next: c.contains(.next) ? (c.lenient(String.self, .next) ?? "") : nil,
            sources: sources,
            stage: stage,
            bucket: bucket,
            checkable: c.lenient(Bool.self, .checkable),
            commissionId: commissionId,
            commissionState: commissionState,
            // A ruling of the wrong shape costs the ruling, never the note.
            review: c.lenient(DaydreamReview.self, .review),
            act: c.lenient(DaydreamAct.self, .act),
            detailed: detailed
        )
    }

    static func defaultPath(for id: String) -> String {
        let escaped = id.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? id
        return "/jkai/daydreams?note=\(escaped)"
    }

    // MARK: - Fallbacks for an older server

    /// Split a body on its final "Next:" paragraph — the loop ends a note
    /// with one when it has a step to suggest. No such paragraph, or an empty
    /// one, is all summary and no step.
    static func split(_ body: String) -> (summary: String, next: String?) {
        let marker = "\n\nNext: "
        guard let range = body.range(of: marker, options: .backwards) else {
            return (body.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }
        let summary = String(body[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let step = String(body[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        // A paragraph break inside the step means the marker was not the
        // last paragraph after all; keep the body whole rather than guess.
        guard !step.isEmpty, !step.contains("\n\n") else {
            return (body.trimmingCharacters(in: .whitespacesAndNewlines), nil)
        }
        return (summary, step)
    }

    /// The list a note belongs in, from what the phone knows. Used for an
    /// older server that sends no bucket, and for a note the reader just
    /// answered here, which the server's bucket has not caught up with.
    /// Your own ruling on the claim (`ruled`) answers a note as surely as a
    /// rating does; a double-check's verdict is information, not your answer.
    static func derivedBucket(feedback: DaydreamVerdict?, commissionState: String?, ruled: Bool = false) -> DaydreamBucket {
        switch commissionState {
        case "queued", "running", "needs_attention": return .motion
        case "completed": return .done
        case "awaiting_approval", "deferred": return .decide
        default: return feedback == nil && !ruled ? .decide : .done
        }
    }

    /// This note with a later copy folded in. A detailed copy always wins; a
    /// plain one (Today's re-read) only brings its verdict, so the sources,
    /// the next step and the list it sits in are not lost to it.
    func merged(with incoming: DaydreamNote) -> DaydreamNote {
        guard detailed, !incoming.detailed else { return incoming }
        guard let verdict = incoming.feedback, verdict != feedback else { return self }
        return DaydreamNote(
            id: id, outcome: outcome, channel: channel, title: title, body: body, createdAt: createdAt,
            url: url, feedback: verdict, summary: summary, next: next, sources: sources,
            stage: nil, bucket: DaydreamNote.derivedBucket(feedback: verdict, commissionState: commissionState,
                                                           ruled: review?.byOwner == true),
            checkable: checkable, commissionId: commissionId, commissionState: commissionState, review: review,
            act: act, detailed: true
        )
    }
}

/// How many notes sit in each list, counted by the site over every note —
/// not just the forty the phone holds.
struct DaydreamPipeline: Decodable, Hashable {
    var decide: Int
    var motion: Int
    var done: Int

    init(decide: Int, motion: Int, done: Int) {
        self.decide = decide
        self.motion = motion
        self.done = done
    }

    enum CodingKeys: String, CodingKey { case decide, motion, done }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        decide = max(0, c.flexInt(.decide) ?? 0)
        motion = max(0, c.flexInt(.motion) ?? 0)
        done = max(0, c.flexInt(.done) ?? 0)
    }

    func count(_ bucket: DaydreamBucket) -> Int {
        switch bucket {
        case .decide: return decide
        case .motion: return motion
        case .done: return done
        }
    }

    /// The site's counts, moved by what happened on this phone since: a note
    /// answered here leaves "to decide" before the next read says so.
    func adjusted(for notes: [DaydreamNote], effective: (DaydreamNote) -> DaydreamBucket) -> DaydreamPipeline {
        var out = self
        for note in notes {
            let now = effective(note)
            guard now != note.bucket else { continue }
            out.add(-1, to: note.bucket)
            out.add(1, to: now)
        }
        return out
    }

    private mutating func add(_ delta: Int, to bucket: DaydreamBucket) {
        switch bucket {
        case .decide: decide = max(0, decide + delta)
        case .motion: motion = max(0, motion + delta)
        case .done: done = max(0, done + delta)
        }
    }
}

/// One week of verdicts, for the Impact card's bars.
struct DaydreamImpactWeek: Decodable, Hashable, Identifiable {
    /// `yyyy-MM-dd`, the week's first day.
    let start: String
    let useful: Int
    let notUseful: Int
    let undecided: Int

    var id: String { start }
    var total: Int { useful + notUseful + undecided }

    init(start: String, useful: Int, notUseful: Int, undecided: Int) {
        self.start = start
        self.useful = useful
        self.notUseful = notUseful
        self.undecided = undecided
    }

    enum CodingKeys: String, CodingKey { case start, useful, notUseful, undecided }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let start = c.lenient(String.self, .start), !start.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .start, in: c, debugDescription: "a week needs a start")
        }
        self.start = start
        useful = max(0, c.flexInt(.useful) ?? 0)
        notUseful = max(0, c.flexInt(.notUseful) ?? 0)
        undecided = max(0, c.flexInt(.undecided) ?? 0)
    }

    /// The week's first day, for the chart's axis. `nil` for a date the
    /// phone cannot read, and the week is then left off the chart.
    var date: Date? {
        let format = DateFormatter()
        format.locale = Locale(identifier: "en_US_POSIX")
        format.timeZone = TimeZone(identifier: "UTC")
        format.dateFormat = "yyyy-MM-dd"
        return format.date(from: String(start.prefix(10)))
    }
}

/// Whether the notes are worth having: the share you called worth knowing,
/// against the window before, and what came of them.
struct DaydreamImpact: Decodable, Hashable {
    let windowDays: Int
    /// 0…1. `nil` when nothing in the window was answered.
    let hitRate: Double?
    let previousHitRate: Double?
    let noticed: Int
    let rated: Int
    let useful: Int
    let actedOn: Int
    let result: Int
    let weeks: [DaydreamImpactWeek]

    init(windowDays: Int, hitRate: Double?, previousHitRate: Double?, noticed: Int, rated: Int, useful: Int,
         actedOn: Int, result: Int, weeks: [DaydreamImpactWeek]) {
        self.windowDays = windowDays
        self.hitRate = hitRate
        self.previousHitRate = previousHitRate
        self.noticed = noticed
        self.rated = rated
        self.useful = useful
        self.actedOn = actedOn
        self.result = result
        self.weeks = weeks
    }

    enum CodingKeys: String, CodingKey {
        case windowDays, hitRate, previousHitRate, noticed, rated, useful, actedOn, result, weeks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let window = c.flexInt(.windowDays) ?? 28
        windowDays = window > 0 ? window : 28
        hitRate = c.lenient(Double.self, .hitRate).map { min(max($0, 0), 1) }
        previousHitRate = c.lenient(Double.self, .previousHitRate).map { min(max($0, 0), 1) }
        noticed = max(0, c.flexInt(.noticed) ?? 0)
        rated = max(0, c.flexInt(.rated) ?? 0)
        useful = max(0, c.flexInt(.useful) ?? 0)
        actedOn = max(0, c.flexInt(.actedOn) ?? 0)
        result = max(0, c.flexInt(.result) ?? 0)
        weeks = c.lossy(DaydreamImpactWeek.self, .weeks)
    }

    /// "72%", or nil when there is no rate to show.
    var hitRateText: String? { hitRate.map { "\(Int(($0 * 100).rounded()))%" } }

    /// Percentage points against the window before; nil without both.
    var deltaPoints: Int? {
        guard let hitRate, let previousHitRate else { return nil }
        return Int(((hitRate - previousHitRate) * 100).rounded())
    }

    /// The share of what was noticed that got an answer, 0…1.
    var answeredShare: Double? {
        guard noticed > 0 else { return nil }
        return min(1, Double(rated) / Double(noticed))
    }
}

/// `{ "notes": [...] }` — the Today block and the scoped endpoint's answer.
/// With `?detail=1` the site adds `pipeline` and `impact`; either may be
/// absent or null, and a wrong shape is the same as absent.
///
/// Never throws. A `daydream` key that arrives as something other than an
/// object must cost the Noticed card, not the whole of Today.
struct DaydreamFeed: Decodable, Hashable {
    let notes: [DaydreamNote]
    let pipeline: DaydreamPipeline?
    let impact: DaydreamImpact?

    init(notes: [DaydreamNote], pipeline: DaydreamPipeline? = nil, impact: DaydreamImpact? = nil) {
        self.notes = notes
        self.pipeline = pipeline
        self.impact = impact
    }

    enum CodingKeys: String, CodingKey { case notes, pipeline, impact }

    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
            notes = []
            pipeline = nil
            impact = nil
            return
        }
        notes = c.lossy(DaydreamNote.self, .notes)
        pipeline = c.lenient(DaydreamPipeline.self, .pipeline)
        impact = c.lenient(DaydreamImpact.self, .impact)
    }
}

extension KeyedDecodingContainer {
    /// A count the server might send as 3, 3.0 or "3".
    func flexInt(_ key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite { return Int(value.rounded()) }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Int(value) }
        return nil
    }
}

/// The body of `POST api/native/daydream/feedback`.
struct DaydreamFeedbackRequest: Encodable, Equatable {
    let id: String
    let verdict: DaydreamVerdict
}
