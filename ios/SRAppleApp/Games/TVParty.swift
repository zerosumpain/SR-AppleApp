import Foundation

// sr. tv: a party hosted by the Android TV app. The TV shows a QR for
// `https://strangeramblings.com/games/join/<CODE>`; on an iPhone that page
// first tries `sr://games/join/<CODE>`, which lands here, so a family member
// with the app sits down as themselves rather than as a guest by name.
//
// The party has no stream of its own. `POST /api/native/games/party/<CODE>/join`
// is idempotent for a family member and answers with the current party, so the
// waiting screen re-posts it every few seconds. When the TV starts a game the
// party carries `roomId`: an ordinary room the member is already joined in,
// opened with the room screens every other game uses — or, for a game this
// build has no screen for (`snap-happy`, `biscuit-tower`, `iron-roads`…), the
// party's own web page in a web view (`TVPartyWebScreen`).

/// `sr://games/join/<CODE>`. CODE is four consonants from the TV's alphabet,
/// which has no vowels so a code never spells a word. PURE.
enum TVPartyLink: Equatable {
    case join(code: String)

    /// The letters a code is made of (SR-Main `party.ts`).
    static let alphabet = Set("BCDFGHJKLMNPQRSTVWXZ")
    static let codeLength = 4

    /// The code, upper-cased, when `raw` is the right shape; nil otherwise.
    static func code(_ raw: String) -> String? {
        let code = raw.trimmingCharacters(in: .whitespaces).uppercased()
        guard code.count == codeLength, code.allSatisfy({ alphabet.contains($0) }) else { return nil }
        return code
    }

    /// Nil for anything that is not a party join. Matched BEFORE `GlanceLink`,
    /// which would otherwise read `join` as a room id.
    static func from(url: URL) -> TVPartyLink? {
        guard url.scheme?.lowercased() == "sr", url.host?.lowercased() == "games" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard parts.count == 2, parts[0].lowercased() == "join", let code = code(parts[1]) else { return nil }
        return .join(code: code)
    }

    /// Whether `url` is `sr://games/join/…` at all, valid code or not — so a
    /// mistyped code is answered with a sentence rather than opening a room
    /// called "join".
    static func isJoinShaped(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "sr", url.host?.lowercased() == "games" else { return false }
        return url.pathComponents.filter { $0 != "/" && !$0.isEmpty }.first?.lowercased() == "join"
    }

    /// The party's page on the site, for a game the app cannot play itself.
    static func webPath(code: String) -> String { "games/join/\(code)" }
}

// MARK: - The wire

/// One person at the party.
struct TVPartyMember: Decodable, Equatable, Identifiable {
    let id: String
    let name: String
    /// family | guest — kept as the string, so a new kind never breaks a read.
    let kind: String
    let online: Bool

    private enum CodingKeys: String, CodingKey { case id, name, kind, online }

    init(id: String, name: String, kind: String = "family", online: Bool = true) {
        self.id = id; self.name = name; self.kind = kind; self.online = online
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decodeIfPresent(String.self, forKey: .name)) ?? "Someone"
        kind = (try? c.decodeIfPresent(String.self, forKey: .kind)) ?? "family"
        online = (try? c.decodeIfPresent(Bool.self, forKey: .online)) ?? true
    }
}

/// A game the TV offers, with the site's own name for it.
struct TVPartyGame: Decodable, Equatable, Identifiable {
    let id: String
    let title: String
    let min: Int
    let max: Int

    private enum CodingKeys: String, CodingKey { case id, title, min, max }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = (try? c.decodeIfPresent(String.self, forKey: .title)) ?? GameNames.title(id)
        min = (try? c.decodeIfPresent(Int.self, forKey: .min)) ?? 1
        max = (try? c.decodeIfPresent(Int.self, forKey: .max)) ?? 8
    }
}

/// SR-Main's `PartyView`. `game` is a plain string: a game this build has
/// never heard of is a party to show, not a decode failure.
struct TVPartyView: Decodable, Equatable {
    let id: String
    let code: String
    let tvName: String
    /// lobby | playing, kept as the string.
    let phase: String
    let locked: Bool
    let game: String?
    let members: [TVPartyMember]
    let roomId: String?
    let notice: String?
    let games: [TVPartyGame]
    let serverNow: Double

    private enum CodingKeys: String, CodingKey {
        case id, code, tvName, phase, locked, game, members, roomId, notice, games, serverNow
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        code = try c.decode(String.self, forKey: .code)
        tvName = ((try? c.decodeIfPresent(String.self, forKey: .tvName)) ?? nil).flatMap { $0.isEmpty ? nil : $0 } ?? "the TV"
        phase = (try? c.decodeIfPresent(String.self, forKey: .phase)) ?? "lobby"
        locked = (try? c.decodeIfPresent(Bool.self, forKey: .locked)) ?? false
        game = ((try? c.decodeIfPresent(String.self, forKey: .game)) ?? nil).flatMap { $0.isEmpty ? nil : $0 }
        members = (try? c.decodeIfPresent([TVPartyMember].self, forKey: .members)) ?? []
        roomId = ((try? c.decodeIfPresent(String.self, forKey: .roomId)) ?? nil).flatMap { $0.isEmpty ? nil : $0 }
        let line = ((try? c.decodeIfPresent(String.self, forKey: .notice)) ?? nil)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        notice = (line?.isEmpty ?? true) ? nil : line
        games = (try? c.decodeIfPresent([TVPartyGame].self, forKey: .games)) ?? []
        serverNow = (try? c.decodeIfPresent(Double.self, forKey: .serverNow)) ?? 0
    }

    /// The site's name for the chosen game, else the app's.
    var gameTitle: String? {
        guard let game else { return nil }
        return games.first { $0.id == game }?.title ?? GameNames.title(game)
    }

    /// Who is in, online first: "Sam, Robin and Alex".
    var whoIsIn: String { GameNames.list(members.map(\.name)) }
}

/// `{ party, me: { id } }`. `seat` is read when the site sends it: the party
/// page's own seat for this member, which signs the web view in as them
/// rather than as a second, guest, seat.
struct TVPartyJoinAnswer: Decodable {
    struct Me: Decodable { let id: String }
    let party: TVPartyView
    let me: Me
    var seat: String? = nil

    private enum CodingKeys: String, CodingKey { case party, me, seat }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        party = try c.decode(TVPartyView.self, forKey: .party)
        me = try c.decode(Me.self, forKey: .me)
        seat = (try? c.decodeIfPresent(String.self, forKey: .seat)) ?? nil
    }
}

// MARK: - What the waiting screen does next

/// The step after a party read. PURE.
enum TVPartyStep: Equatable {
    /// Nothing running, or the game already opened from here: keep waiting.
    case wait
    /// A room this app plays: open it on the Games stack.
    case openRoom(id: String, game: String)
    /// A game this build has no screen for: the party's page instead.
    case openWeb(game: String)

    /// `opened`: the room last opened from this screen, so coming back from a
    /// game still running does not throw the person straight back into it.
    static func next(_ party: TVPartyView, opened: String?) -> TVPartyStep {
        guard let room = party.roomId, room != opened else { return .wait }
        let game = party.game ?? ""
        return TVPartyStep.playsNatively(game) ? .openRoom(id: room, game: game) : .openWeb(game: game)
    }

    /// A room game with a screen in this build. The phone's own offline games
    /// are `GameKind`s too, but never a room.
    static func playsNatively(_ game: String) -> Bool {
        guard let kind = GameKind(rawValue: game) else { return false }
        return !kind.playsOnPhone
    }
}

/// Which party a room came from, so a room of a game this build cannot play —
/// found later under "Your games" — can still open the party's page. Recent
/// rooms only: a party lasts an evening.
enum TVPartyRooms {
    private static let key = "tv-party-rooms"
    private static let keep = 30

    static func remember(room: String, code: String, defaults: UserDefaults = .standard) {
        var pairs = (defaults.array(forKey: key) as? [[String]]) ?? []
        pairs.removeAll { $0.first == room }
        pairs.append([room, code])
        defaults.set(Array(pairs.suffix(keep)), forKey: key)
    }

    static func code(for room: String, defaults: UserDefaults = .standard) -> String? {
        let pairs = (defaults.array(forKey: key) as? [[String]]) ?? []
        return pairs.last { $0.first == room && $0.count == 2 }?[1]
    }
}

/// The site's names for games this build does not know, learned from a
/// party's game list, so a row reads "Snap Happy" in the site's words.
enum TVPartyTitles {
    private static let key = "tv-party-titles"

    static func learn(_ games: [TVPartyGame], defaults: UserDefaults = .standard) {
        var titles = (defaults.dictionary(forKey: key) as? [String: String]) ?? [:]
        var changed = false
        for game in games where GameKind(rawValue: game.id) == nil && !game.title.isEmpty && titles[game.id] != game.title {
            titles[game.id] = game.title
            changed = true
        }
        if changed { defaults.set(titles, forKey: key) }
    }

    static func title(_ game: String, defaults: UserDefaults = .standard) -> String? {
        (defaults.dictionary(forKey: key) as? [String: String])?[game]
    }
}

// MARK: - The waiting screen's model

@MainActor
final class TVPartyStore: ObservableObject {
    enum State: Equatable {
        case joining
        case waiting(TVPartyView)
        /// The server's sentence. `web`: the app itself cannot join (not
        /// connected to the site), so the party's page is offered instead.
        case failed(String, web: Bool)
    }

    let code: String
    @Published private(set) var state: State = .joining
    /// The room last opened from here (`TVPartyStep.next`).
    @Published var opened: String?
    /// The party page's seat for this member, when the site sent one.
    private(set) var seat: String?
    private(set) var partyId: String?

    /// Every three seconds while the waiting screen is up.
    static let pollInterval: TimeInterval = 3

    init(code: String) { self.code = code }

    var party: TVPartyView? {
        if case .waiting(let party) = state { return party }
        return nil
    }

    /// One join, which is also the read: the current party, or the server's sentence.
    func refresh() async {
        guard TVPartyLink.code(code) != nil else {
            state = .failed("That isn\u{2019}t a code a TV shows. It\u{2019}s four letters, like BCDF \u{2014} scan the TV\u{2019}s QR again.", web: false)
            return
        }
        do {
            let answer: TVPartyJoinAnswer = try await SiteClient.shared.send(
                "api/native/games/party/\(code)/join", method: "POST", body: Data("{}".utf8))
            if let seat = answer.seat, !seat.isEmpty { self.seat = seat }
            partyId = answer.party.id
            TVPartyTitles.learn(answer.party.games)
            if let room = answer.party.roomId { TVPartyRooms.remember(room: room, code: code) }
            state = .waiting(answer.party)
        } catch is CancellationError {
            return
        } catch let error as URLError where error.code == .cancelled {
            return
        } catch let error as SiteError {
            switch error {
            case .unpaired, .expired:
                state = .failed(error.localizedDescription, web: true)
            default:
                // Refusals (403 / 404 / 409 / 423) are the party's answer and
                // end the wait. A 5xx or a lost signal with a party already on
                // screen keeps showing it; the next poll tries again.
                if party != nil, (error.status ?? 500) >= 500 { return }
                state = .failed(error.localizedDescription, web: false)
            }
        } catch {
            if party != nil { return }
            state = .failed(error.localizedDescription, web: false)
        }
    }

    /// Join, then keep reading while the screen is up. Ends with the task
    /// (`.task` cancels it when the screen goes, including under a pushed game).
    func run(step: @escaping @MainActor (TVPartyStep) -> Void) async {
        while !Task.isCancelled {
            await refresh()
            if case .failed = state { return }
            if let party { step(TVPartyStep.next(party, opened: opened)) }
            try? await Task.sleep(nanoseconds: UInt64(Self.pollInterval * 1_000_000_000))
        }
    }
}
