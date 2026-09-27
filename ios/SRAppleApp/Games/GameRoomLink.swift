import Foundation
import QuartzCore

/// One room's connection to the site, whichever game it is.
///
/// The room arrives over the site's SSE stream (`api/native/games/<id>/stream`,
/// frames `{"type":"room","room":…}`); every action is a POST that answers with
/// the room too. The stream is reopened on a drop and when the scene comes
/// back; a stream that cannot be opened at all (demo mode answers 404) falls
/// back to re-reading the snapshot on the same backoff, so the screen never
/// sits on a stale room without trying.
///
/// Every payload's `serverNow` feeds `clock`, so a game's deadlines can be read
/// on the phone's own monotonic clock. The game's store owns what the room
/// MEANS; this owns getting it.
@MainActor
final class GameRoomLink {
    let roomId: String

    /// Every room the server sends — snapshot, stream frame, action answer.
    var onRoom: @MainActor (GameRoom) -> Void = { _ in }
    /// The room is gone (404, 403) or closed. Called once.
    var onEnd: @MainActor () -> Void = {}
    /// Something to tell the player.
    var onNote: @MainActor (GameLinkNote) -> Void = { _ in }

    private(set) var clock = GameClock()
    private(set) var ended = false
    private var hasRoom = false
    private var streamTask: Task<Void, Never>?
    private var joinTried = false
    private let client = SiteClient.shared

    init(roomId: String) {
        self.roomId = roomId
    }

    /// Monotonic milliseconds — the phone's side of `GameClock`.
    static func nowMs() -> Double { CACurrentMediaTime() * 1000 }

    /// The server's clock, now, as well as this phone can tell.
    func serverNow() -> Double? { clock.server(Self.nowMs()) }

    // MARK: - Connection

    /// Open (or reopen) the room. Idempotent.
    func open() {
        guard streamTask == nil, !ended else { return }
        streamTask = Task { [weak self] in
            var backoff: UInt64 = 1
            while !Task.isCancelled {
                guard let self, !self.ended else { return }
                await self.refresh()
                if self.ended || Task.isCancelled { return }
                let delivered = await self.listen()
                if Task.isCancelled || self.ended { return }
                // A stream that carried frames earns a quick retry; one that
                // never opened backs off, up to ten seconds.
                backoff = delivered ? 1 : min(backoff * 2, 10)
                try? await Task.sleep(nanoseconds: backoff * 1_000_000_000)
            }
        }
    }

    /// Close the stream. The room screen calls this when it goes away and when
    /// the scene leaves the foreground.
    func close() {
        streamTask?.cancel()
        streamTask = nil
    }

    /// The snapshot: `GET api/native/games/<id>`, timed as a round trip.
    func refresh() async {
        let sent = Self.nowMs()
        do {
            let envelope: GameRoomEnvelope = try await client.send("api/native/games/\(roomId)")
            clock.record(serverNow: envelope.room.serverNow, sentAt: sent, receivedAt: Self.nowMs())
            deliver(envelope.room)
        } catch SiteError.status(let code, _) where code == 404 {
            end()
        } catch SiteError.status(let code, _) where code == 403 {
            onNote(.error("You are not in this game."))
            end()
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled { return }
            onNote(hasRoom ? .reconnecting : .error(error.localizedDescription))
        }
    }

    /// Read the stream until it ends. True when at least one frame arrived.
    private func listen() async -> Bool {
        var delivered = false
        do {
            let stream = try client.stream(path: "api/native/games/\(roomId)/stream")
            for try await frame in stream {
                if Task.isCancelled { break }
                let received = Self.nowMs()
                guard let decoded = try? JSONDecoder().decode(GameStreamFrame.self, from: frame.data),
                      decoded.type == "room", let room = decoded.room else { continue }
                delivered = true
                clock.record(serverNow: room.serverNow, receivedAt: received)
                deliver(room)
                onNote(.reconnected)
            }
        } catch {
            // Dropped or refused. The loop re-reads the snapshot next, which
            // is what tells a gone room (404) from a flaky connection.
        }
        return delivered
    }

    /// The room is over for this screen. Idempotent.
    func end() {
        guard !ended else { return }
        ended = true
        close()
        onEnd()
    }

    private func deliver(_ room: GameRoom) {
        guard !ended else { return }
        hasRoom = true
        onRoom(room)
        if room.phase == .closed {
            end()
            return
        }
        // An invitee who opened the room — from the notification or the list —
        // is in it. Once: a decline elsewhere must not be undone by this.
        if room.phase == .lobby, room.me?.status == "invited", !joinTried {
            joinTried = true
            Task { _ = await self.post(GameActionBody(action: "join")) }
        }
    }

    // MARK: - Actions

    /// POST an action. The answering room is delivered like any other.
    func post(_ body: GameActionBody) async -> GamePostOutcome {
        let sent = Self.nowMs()
        do {
            let data = try await client.post("api/native/games/\(roomId)", body: try JSONEncoder().encode(body))
            let received = Self.nowMs()
            if let envelope = try? JSONDecoder().decode(GameRoomEnvelope.self, from: data) {
                clock.record(serverNow: envelope.room.serverNow, sentAt: sent, receivedAt: received)
                deliver(envelope.room)
            }
            return .ok
        } catch SiteError.status(let code, _) where code == 404 {
            end()
            return .gone
        } catch SiteError.status(let code, _) where code == 409 {
            return .wrongPhase
        } catch SiteError.status(let code, let sentence) where code == 400 {
            return .refused(sentence)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}

extension GameRoomLink {
    /// The host asks more people into a lobby. A one-off POST: the room that
    /// answers reaches the lobby over its own stream like any other change.
    static func invite(_ playerIds: [String], to roomId: String) async -> GamePostOutcome {
        await GameRoomLink(roomId: roomId).post(GameActionBody(action: "invite", invite: playerIds))
    }
}

/// What a `GameRoomLink` has to say.
enum GameLinkNote: Equatable {
    /// The stream dropped with a room on screen; it is being reopened.
    case reconnecting
    /// A frame arrived: any "Reconnecting…" can go.
    case reconnected
    case error(String)
}

/// How an action went.
enum GamePostOutcome: Equatable {
    case ok
    /// 404: the room has gone. The link has ended.
    case gone
    /// 409: wrong phase — a tap for a round that closed, a guess after the
    /// time ran out. The stream already carries the truth.
    case wrongPhase
    /// 400, with the server's sentence for the player.
    case refused(String)
    case failed(String)
}

/// What every game's room store offers the shared lobby and countdown views.
@MainActor
protocol GameRoomStoring: ObservableObject {
    var busy: Bool { get }
    func serverNow() -> Double?
    func act(_ action: String) async -> Bool
}
