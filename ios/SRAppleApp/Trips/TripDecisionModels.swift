import Foundation

// v8 (2026-10-21): propose, research, ask — the planner's decisions as the
// phone receives them.
//
// A mirror of SR-Main `src/lib/trips/decisions.ts` and the wire contract in
// `docs/superpowers/specs/2026-10-21-trips-propose-ask.md`. As in
// `TripModels.swift`, property names ARE the JSON keys, so drift shows up as
// a failed decode of the shared fixture in `TripDecisionTests`
// (`Fixtures/TripDecisions/decisions-wire.json`, the same file the server
// tests read).
//
// Every enum decodes an unknown raw value as `.unknown` instead of failing the
// bundle: a later server may add a kind, and a trip must stay readable.
//
// Foundation only: the Linux harness compiles this with the solver port.

// MARK: - The brief

/// Where a fact came from. Shown on every brief chip.
enum FactSource: String, Codable, Hashable {
    case you, notes, found, assumed
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FactSource(rawValue: raw) ?? .unknown
    }

    /// "You said", "From your notes", "Found", "Assumed".
    var label: String {
        switch self {
        case .you: return "You said"
        case .notes: return "From your notes"
        case .found: return "Found"
        case .assumed: return "Assumed"
        case .unknown: return "Noted"
        }
    }
}

struct BriefItem: Codable, Hashable, Identifiable {
    var key: String
    /// destination, dates, travellers, pace, modes, stay, transport, booking, must, preference, constraint, assumption.
    var kind: String
    var label: String
    var detail: String?
    /// Where it came from (`origin` on the wire: `source` is reserved for memory, which never reaches the phone).
    var origin: FactSource
    var note: String?
    var ref: String?
    var editable: Bool

    var id: String { key }
    var isAssumed: Bool { origin == .assumed }
}

struct TripBrief: Codable, Hashable {
    var items: [BriefItem]
    var assumed: Int
    var missing: [String]
}

// MARK: - Plan differences

struct PlanChange: Codable, Hashable {
    /// added, removed, moved, retimed, dropped.
    var kind: String
    var wishId: String?
    var title: String
    var date: String?
    var fromDate: String?
    var fromMin: Double?
    var toMin: Double?
    var reason: String?
}

struct PlanDiff: Codable, Hashable {
    var lines: [String]
    var changes: [PlanChange]
    var dates: [String]
    var walkDeltaM: Double?
    var dropped: [String]

    static let empty = PlanDiff(lines: [], changes: [], dates: [], walkDeltaM: nil, dropped: [])
}

// MARK: - Proposals

enum ProposalKind: String, Codable, Hashable {
    case shape, day, swap, fill, fix, change, replan
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProposalKind(rawValue: raw) ?? .unknown
    }
}

enum ProposalStatus: String, Codable, Hashable {
    case open, accepted, rejected, superseded, expired
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProposalStatus(rawValue: raw) ?? .unknown
    }
}

/// "Like this, but…" — a nudge asks for new alternatives from the research pack.
enum Nudge: String, Codable, Hashable, CaseIterable, Identifiable {
    case closer
    case cheaper
    case lessWalking = "less-walking"
    case quieter
    case moreLikeThis = "more-like-this"

    var id: String { rawValue }
    var label: String {
        switch self {
        case .closer: return "Closer"
        case .cheaper: return "Cheaper"
        case .lessWalking: return "Less walking"
        case .quieter: return "Quieter"
        case .moreLikeThis: return "More like this"
        }
    }
}

/// Why a proposal was turned down — sent back, and learned from.
enum RejectReason: String, Codable, Hashable, CaseIterable, Identifiable {
    case tooFar = "too-far"
    case tooBusy = "too-busy"
    case notForUs = "not-for-us"
    case beenBefore = "been-before"
    case other

    var id: String { rawValue }
    var label: String {
        switch self {
        case .tooFar: return "Too far"
        case .tooBusy: return "Too busy"
        case .notForUs: return "Not for us"
        case .beenBefore: return "Been before"
        case .other: return "Something else"
        }
    }
}

struct ProposalScope: Codable, Hashable {
    var date: String?
    /// A `DayStage` raw value.
    var stage: String?
    var stopId: String?
    var wishId: String?
}

struct ProposalTradeoffs: Codable, Hashable {
    var fits: Bool
    var fitText: String?
    var walkMin: Double?
    var walkKmPerDay: Double?
    var earlyStarts: Double?
    var toBook: Double?
    var costText: String?
    var indoor: Bool?
    var kidFriendly: Bool?
    var lessVisited: Bool
    var pushesOut: [String]
    var moves: [Move]

    struct Move: Codable, Hashable {
        var title: String
        var from: String
        var to: String
    }
}

struct ShapeSummary: Codable, Hashable {
    struct Day: Codable, Hashable, Identifiable {
        var date: String
        var line: String
        var id: String { date }
    }

    var headline: String
    var days: [Day]
    var leavesOut: [String]
}

struct ProposalPlace: Codable, Hashable {
    var name: String
    var location: TripLatLng
}

struct WireSource: Codable, Hashable {
    var url: String
    var title: String?
}

struct TripProposal: Codable, Hashable, Identifiable {
    var id: String
    var groupId: String
    var kind: ProposalKind
    var title: String
    var why: String
    var scope: ProposalScope
    /// The checked ops accepting it replays on the server. The phone never sends them back.
    var ops: [TripJSON]
    var diff: PlanDiff
    var tradeoffs: ProposalTradeoffs
    var evidence: [WireSource]
    var place: ProposalPlace?
    var image: PlaceImage?
    var packPlaceId: String?
    var shape: ShapeSummary?
    /// The days it changes, as solved — drawn as the ghost on the map.
    var preview: [PlannedDay]
    var basedOnVersion: Int?
    var status: ProposalStatus
    var reason: String?
    var createdAt: String
    var decidedAt: String?
}

// MARK: - Questions

enum QuestionStatus: String, Codable, Hashable {
    case open, answered, skipped, expired, withdrawn
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = QuestionStatus(rawValue: raw) ?? .unknown
    }
}

struct QuestionAnswer: Codable, Hashable, Identifiable {
    var id: String
    var label: String
    var ops: [TripJSON]
    var brief: TripJSON?
    var remember: String?
    /// What choosing it changes; nil for the answer already assumed.
    var summary: String?
    var changes: Double
}

struct TripQuestion: Codable, Hashable, Identifiable {
    struct Affects: Codable, Hashable {
        var dates: [String]
        var stops: Double
    }

    var id: String
    var key: String
    /// brief, tie, clash, research, reaction, day, after, planner.
    var origin: String
    var prompt: String
    var why: String
    var answers: [QuestionAnswer]
    var defaultAnswerId: String
    var appliedDefault: Bool
    var ifSkipped: String
    var affects: Affects
    var impact: Double
    /// owner, parents, family.
    var audience: String
    var deadline: String?
    var status: QuestionStatus
    var answerId: String?
    var answeredByName: String?
    /// Family votes so far: answer id → names.
    var votes: [String: [String]]
    var basedOnVersion: Int?
    var createdAt: String
    var answeredAt: String?

    var defaultAnswer: QuestionAnswer? { answers.first { $0.id == defaultAnswerId } }
    var chosenAnswer: QuestionAnswer? { answers.first { $0.id == answerId } }
}

// MARK: - The research pack

struct PackPlace: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var kind: String
    var tags: [String]
    var place: TripPlace
    var why: String?
    var neighbourhood: String?
    var durationMin: Double?
    var indoor: Bool?
    var kidFriendly: Bool?
    var costText: String?
    var lessVisited: Bool
    var bookingRequired: Bool?
    var bookAheadDays: Double?
    var facts: TripFacts?
    var image: PlaceImage?
    var wikidata: String?
    var sources: [WireSource]
    /// candidate, planned, rejected.
    var status: String
    var rejectReason: String?
    var wishId: String?
    var checkedAt: String?
}

struct PackCalendarItem: Codable, Hashable {
    var date: String?
    /// closure, holiday, event, strike, weather, sun, other.
    var kind: String
    var text: String
    var placeId: String?
    var sources: [WireSource]
}

struct PackNeighbourhood: Codable, Hashable {
    var name: String
    var line: String
    var places: [String]
}

struct PackSummary: Codable, Hashable {
    struct Counts: Codable, Hashable {
        var places: Double
        var food: Double
        var toBook: Double
        var lessVisited: Double
        var rainy: Double
    }

    /// none, building, ready, failed.
    var status: String
    var stage: String?
    var builtAt: String?
    var refreshedAt: String?
    var counts: Counts
    var calendar: [PackCalendarItem]
    var neighbourhoods: [PackNeighbourhood]
    var highlights: [String]

    var isReady: Bool { status == "ready" }
    var isBuilding: Bool { status == "building" }
}

/// `GET …/pack` → the summary and the places.
struct PackReply: Codable, Hashable {
    var pack: PackSummary
    var places: [PackPlace]
}

// MARK: - Starting a trip

/// What the owner's notes already hold, offered for a one-tap confirm.
struct NoteFact: Codable, Hashable, Identifiable {
    var id: String
    /// stay, transport, booking, traveller, preference.
    var kind: String
    var label: String
    var detail: String?
    var ops: [TripJSON]
    var ref: String?
}

struct NotesReply: Codable, Hashable {
    var notes: [NoteFact]
}

struct TripStart: Codable, Hashable {
    struct Traveller: Codable, Hashable {
        var name: String
        var age: Double?
        var personId: String?
    }

    var destination: String
    var startDate: String
    var endDate: String
    var travellers: [Traveller]
    /// relaxed, normal, packed.
    var pace: String
    var confirmNotes: [String]
    var text: String?
}

// MARK: - Jobs with stages

enum JobStageState: String, Codable, Hashable {
    case waiting, running, done, failed, skipped
    case unknown

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = JobStageState(rawValue: raw) ?? .unknown
    }
}

struct JobStage: Codable, Hashable, Identifiable {
    var key: String
    var label: String
    var state: JobStageState
    var detail: String?
    var id: String { key }
}

/// A job as the v8 server reports it (stages and trip id; status may be `cancelled`).
struct StagedJob: Codable, Hashable, Identifiable {
    var id: String
    var kind: String
    var status: String
    var tripId: String?
    var startedAt: String
    var finishedAt: String?
    var result: TripJSON?
    var error: String?
    var stages: [JobStage]?
}

// MARK: - Replies to decisions

/// `GET …/decisions` (and the same fields on the v8 bundle).
struct DecisionsWire: Codable, Hashable {
    var brief: TripBrief
    var questions: [TripQuestion]
    var answered: [TripQuestion]
    var proposals: [TripProposal]
    var pack: PackSummary
}

struct UndoPoint: Codable, Hashable {
    var toVersion: Int
}

/// `POST …/proposals/:pid {accept}` and `POST …/questions/:qid`: what changed, and how to undo it.
struct DecisionResult: Codable, Hashable {
    var proposal: TripProposal?
    var question: TripQuestion?
    var planVersion: Int?
    var changes: [String]?
    var diff: PlanDiff?
    var undo: UndoPoint?
    /// A lasting preference the answer offers to remember (never saved without a tap).
    var remember: String?
    /// 409 on accept: the plan moved; this is the re-checked proposal to show again.
    var stale: Bool?
}

/// `POST …/proposals` → one group of alternatives.
struct ProposalGroupReply: Codable, Hashable {
    var proposals: [TripProposal]
}

/// `POST …/undo`.
struct UndoResult: Codable, Hashable {
    var planVersion: Int?
    var changes: [String]
    var diff: PlanDiff?
}
