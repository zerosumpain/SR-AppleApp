import Foundation
import UIKit

/// What this person may use in the app, as the site decided it.
///
/// The owner adds a family member to the site's access groups; the site files
/// the answer in that person's household view (`access`) and repeats it on
/// `/api/native/me`. Everything here is the phone OBEYING that answer, never
/// deciding it: a feature the person lacks is not greyed out or explained, it
/// is absent — no tab, no card, no button, no Siri phrase that opens it. The
/// server refuses those calls anyway (members get 403 on everything outside
/// their lanes); hiding them is so the app never offers what it cannot do.
///
/// Every flag decodes as absent-means-false. A site that has not heard of a
/// flag has not granted it.
struct AppAccess: Codable, Equatable {
    var owner = false
    var chat = false
    var news = false
    var research = false
    var notes = false
    var intel = false
    var family = false
    /// Family games (`games:self` on the site): the Games tab and its invites.
    var games = false
    /// Where the answer came from: "view" (the household view — preferred,
    /// because it is what the owner's access groups were pushed into) or
    /// "site" (`/api/native/me`, the fallback for a phone whose view carries
    /// none). Nil in anything built in code.
    var source: String? = nil

    static let everything = AppAccess(owner: true, chat: true, news: true, research: true, notes: true, intel: true, family: true, games: true)
    static let nothing = AppAccess()

    init(owner: Bool = false, chat: Bool = false, news: Bool = false, research: Bool = false,
         notes: Bool = false, intel: Bool = false, family: Bool = false, games: Bool = false,
         source: String? = nil) {
        self.owner = owner; self.chat = chat; self.news = news; self.research = research
        self.notes = notes; self.intel = intel; self.family = family; self.games = games
        self.source = source
    }

    private enum CodingKeys: String, CodingKey { case owner, chat, news, research, notes, intel, family, games, source }

    /// Lenient: a missing or mistyped flag is false, never a thrown decode —
    /// this rides inside the household view and the persisted upload queue,
    /// and neither may be lost to one odd field.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func flag(_ key: CodingKeys) -> Bool { ((try? c.decodeIfPresent(Bool.self, forKey: key)) ?? nil) ?? false }
        owner = flag(.owner); chat = flag(.chat); news = flag(.news); research = flag(.research)
        notes = flag(.notes); intel = flag(.intel); family = flag(.family); games = flag(.games)
        source = (try? c.decodeIfPresent(String.self, forKey: .source)) ?? nil
    }

    /// The flags alone. Two answers from different sources that grant the same
    /// things are the same answer to every screen.
    var flags: AppAccess { var copy = self; copy.source = nil; return copy }
}

/// A one-time site pairing code the site put in this person's view, because
/// their phone asked for one (`POST /api/apple/site-pair`). Consumed once.
struct SitePairOffer: Codable, Equatable {
    let server: String
    let code: String
    let expiresAt: String?

    /// What the QR scanner would have produced, so the same pairing path runs.
    var pairing: SitePairing { SitePairing(type: "sr-native-pair", version: 1, server: server, code: code) }

    func expired(now: Date = Date()) -> Bool {
        guard let expiresAt, let date = isoDate(expiresAt) else { return false }
        return date <= now
    }
}

/// The `access` block of a household view: the flags, and possibly a pairing
/// code. Kept apart from `AppAccess` so a pairing code is never persisted.
struct ViewAccess: Codable, Equatable {
    let flags: AppAccess
    let sitePair: SitePairOffer?

    init(flags: AppAccess, sitePair: SitePairOffer? = nil) {
        self.flags = flags
        self.sitePair = sitePair
    }

    private enum CodingKeys: String, CodingKey { case sitePair }

    init(from decoder: Decoder) throws {
        flags = try AppAccess(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // An unreadable code costs the code, not the flags.
        sitePair = (try? c.decodeIfPresent(SitePairOffer.self, forKey: .sitePair)) ?? nil
    }

    func encode(to encoder: Encoder) throws {
        try flags.flags.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encodeIfPresent(sitePair, forKey: .sitePair)
    }
}

/// Every access decision, as pure functions of plain values — so each rule is
/// a unit test rather than something only a device can show.
enum AccessPolicy {
    /// What the app treats this person as allowed.
    ///
    /// Known → that answer (an owner gets everything, whatever else is set).
    /// Unknown — never answered, or a site older than access groups — splits
    /// on the SITE credential: every existing owner install holds one, and a
    /// member could only have got one by the automatic path, which needs a
    /// known answer first. So a site credential with no answer is John's phone
    /// and stays exactly as it was; anything else fails closed.
    static func resolve(known: AppAccess?, sitePaired: Bool) -> AppAccess {
        if let known { return known.owner ? .everything : known.flags }
        return sitePaired ? .everything : .nothing
    }

    /// The tab bar, in its fixed order, holding only what may be opened.
    /// Today and Health are everyone's: Health is at least this phone's own
    /// uploads. iOS adds "More" by itself only past five.
    ///
    /// Games sits straight after Family: a family member given both has four
    /// tabs and sees it on the bar; the owner, with seven, finds it under More.
    static func tabs(for access: AppAccess) -> [Router.Tab] {
        [Router.Tab.today, .chat, .health, .family, .games, .news, .flows].filter { allows($0, access) }
    }

    static func allows(_ tab: Router.Tab, _ access: AppAccess) -> Bool {
        switch tab {
        case .today, .health: return true
        case .chat: return access.owner || access.chat
        case .news: return access.owner || access.news
        case .family: return access.owner || access.family
        case .games: return access.owner || access.games
        case .flows: return access.owner
        }
    }

    /// Whether this phone should ask the site for a member credential: a known
    /// member, entitled to something that needs one, without one yet. An owner
    /// never auto-pairs — the QR flow is theirs.
    ///
    /// Games counts: its rooms live on the site (`/api/native/games`), so a
    /// member given games and nothing else still needs a site credential.
    static func wantsSitePair(known: AppAccess?, sitePaired: Bool) -> Bool {
        guard let known, !known.owner, !sitePaired else { return false }
        return needsSite(known)
    }

    /// Whether a site credential this phone holds must go: a known member who
    /// has lost every lane it was for. Never when the site itself says the
    /// credential is the owner's — a stale view must not sign John out.
    static func signsOutSite(known: AppAccess?, sitePaired: Bool, siteRole: String?) -> Bool {
        guard sitePaired, let known, !known.owner, siteRole != "owner" else { return false }
        return !needsSite(known)
    }

    /// The lanes a member's site credential is for.
    private static func needsSite(_ access: AppAccess) -> Bool {
        access.chat || access.news || access.games
    }

    /// How often a member phone re-asks for a pairing code.
    static let pairRequestInterval: TimeInterval = 300

    static func pairRequestDue(last: Date?, now: Date = Date()) -> Bool {
        guard let last else { return true }
        return now.timeIntervalSince(last) >= pairRequestInterval
    }

    /// The Home Screen quick actions this person may take.
    static func quickActions(for access: AppAccess) -> [QuickActionKind] {
        QuickActionKind.allCases.filter { kind in
            switch kind {
            case .ask: return allows(.chat, access)
            case .health, .sync: return true
            }
        }
    }

    /// The news verbs a story offers. The site's own per-response `can` wins;
    /// a site that sends none is older than member access, and only an owner
    /// could be reading it — so the fallback is the person's own flags.
    static func newsActions(can: NewsCan?, access: AppAccess) -> [NewsAction] {
        let graph = can?.graph ?? (access.owner || access.intel)
        let note = can?.note ?? (access.owner || access.notes)
        let research = can?.research ?? (access.owner || access.research)
        return [NewsAction.favourite, .graph, .note, .research].filter { action in
            switch action {
            case .favourite: return true
            case .graph: return graph
            case .note: return note
            case .research: return research
            }
        }
    }
}

/// What the news desk says this person may do with a story. Optional per
/// field: absent means the site did not say, and the fallback decides.
struct NewsCan: Decodable, Equatable {
    let graph: Bool?
    let research: Bool?
    let note: Bool?
    let ask: Bool?
}

/// The Home Screen quick actions, by the type string iOS hands back.
enum QuickActionKind: String, CaseIterable {
    case ask = "com.strangeramblings.com.appleapp.ask"
    case health = "com.strangeramblings.com.appleapp.health"
    case sync = "com.strangeramblings.com.appleapp.sync"

    @MainActor var item: UIApplicationShortcutItem {
        let (title, icon): (String, String) = {
            switch self {
            case .ask: return ("Ask jkai", "bubble.left.and.text.bubble.right")
            case .health: return ("Health today", "heart.text.square")
            case .sync: return ("Sync now", "arrow.triangle.2.circlepath")
            }
        }()
        return UIApplicationShortcutItem(type: rawValue, localizedTitle: title, localizedSubtitle: nil,
                                         icon: UIApplicationShortcutIcon(systemImageName: icon))
    }
}

/// The one place the app's access lives.
///
/// Persisted in the upload queue's state file (`PersistedState.access`), so a
/// relaunch — including a background one with no network — knows at once what
/// to show and what to leave alone. `shared` because the entry points that must
/// obey it are not all views: the app delegate's quick actions and background
/// task, the Siri intents, and the stores' own guards.
@MainActor
final class AccessStore: ObservableObject {
    static let shared = AccessStore()

    /// What every screen obeys.
    @Published private(set) var current: AppAccess
    /// The site's last answer, or nil if it never gave one.
    @Published private(set) var known: AppAccess?
    /// A pairing code waiting for `ContentView` to use.
    @Published private(set) var offer: SitePairOffer?
    /// "owner" or "member", from `/api/native/me`. In memory only.
    private(set) var siteRole: String?

    private weak var outbox: Outbox?
    private var sitePaired: Bool
    private var lastPairRequest: Date?
    /// Codes already tried, so a code the site refused is not retried every
    /// fifteen seconds while the Family tab re-reads the same view.
    private var triedCodes: Set<String> = []

    init(outbox: Outbox? = nil, sitePaired: Bool? = nil) {
        let paired = sitePaired ?? SiteClient.shared.isPaired
        self.outbox = outbox
        self.sitePaired = paired
        known = outbox?.state.access
        current = AccessPolicy.resolve(known: outbox?.state.access, sitePaired: paired)
        applyDemo()
    }

    /// Read the persisted answer. Called once the upload queue is open.
    func attach(_ outbox: Outbox) {
        self.outbox = outbox
        known = outbox.state.access
        recompute()
    }

    /// Adopt a household view's `access`. Nil — an older site, or no view
    /// yet — changes nothing.
    func adopt(view access: ViewAccess?) {
        guard let access, !Self.isDemo else { return }
        var flags = access.flags.flags
        flags.source = "view"
        store(flags)
        if let pair = access.sitePair, !triedCodes.contains(pair.code), !pair.expired() {
            offer = pair
        } else if access.sitePair == nil {
            offer = nil
        }
    }

    /// Adopt `/api/native/me`. Only fills in where no view has answered: the
    /// view is what the owner's groups were pushed into.
    func adopt(siteRole role: String?, flags: AppAccess) {
        siteRole = role
        guard let role, !Self.isDemo, known?.source != "view" else { return }
        var answer = flags.flags
        answer.owner = role == "owner"
        answer.source = "site"
        store(answer)
    }

    func siteChanged(paired: Bool) {
        guard paired != sitePaired else { return }
        sitePaired = paired
        if !paired { siteRole = nil }
        recompute()
    }

    /// Take the waiting code, once.
    func takeOffer() -> SitePairOffer? {
        guard let offer else { return nil }
        triedCodes.insert(offer.code)
        self.offer = nil
        return offer
    }

    /// Whether to POST `site-pair {wanted: true}` now; records the attempt.
    func claimPairRequest(now: Date = Date()) -> Bool {
        guard AccessPolicy.wantsSitePair(known: known, sitePaired: SiteClient.shared.isPaired),
              AccessPolicy.pairRequestDue(last: lastPairRequest, now: now) else { return false }
        lastPairRequest = now
        return true
    }

    var tabs: [Router.Tab] { AccessPolicy.tabs(for: current) }
    func allows(_ tab: Router.Tab) -> Bool { AccessPolicy.allows(tab, current) }

    /// The owner's site lane: the site is paired AND this is the owner. Every
    /// store that reads an owner-only endpoint (today, alerts, connections,
    /// health, daydream, flows) guards on this rather than on `isPaired`,
    /// because a member's phone is site-paired now too — and those endpoints
    /// would only 403 it.
    static var ownerSite: Bool { SiteClient.shared.isPaired && shared.current.owner }

    private func store(_ answer: AppAccess) {
        if let outbox, outbox.state.access != answer {
            try? outbox.change { $0.access = answer }
        }
        known = answer
        recompute()
    }

    private func recompute() {
        let next = AccessPolicy.resolve(known: known, sitePaired: sitePaired)
        if next != current { current = next }
        applyDemo()
    }

    private static var isDemo: Bool {
        #if DEBUG
        return SRDemo.isOn
        #else
        return false
        #endif
    }

    /// Demo mode (`-SRDemo`, DEBUG only) is the owner, unless `-SRDemoMember`
    /// asks for a family member with neither chat nor news — the screenshot
    /// that proves those tabs are not there at all.
    private func applyDemo() {
        #if DEBUG
        if SRDemo.isOn { current = SRDemo.access }
        #endif
    }
}
