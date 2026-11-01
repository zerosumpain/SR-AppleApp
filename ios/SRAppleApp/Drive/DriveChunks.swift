import Foundation

// Big files into Drive a piece at a time: a resumable upload session
// (`api/native/drive/uploads`), for anything over the single-shot limit.
//
// SHARED with the share extension (`SRAppleShare`, see watch.yml), which runs
// the same steps in the foreground. Foundation only: the Linux harness
// compiles it, so the chunk plan, the resume decisions and what every answer
// means are unit tests rather than a reading of the delegate.
//
// The session, step by step:
//   1. `POST uploads?space=` {folder, filename, type, size, sha256, takenAt?}
//      → 201 a session, or 200 `{file, duplicate: true}` (nothing to send).
//   2. `PUT uploads/<id>?space=&offset=N`, one chunk as the raw body
//      → 200 `{received}`; 409 `{error, received}` says where to carry on.
//   3. `POST uploads/<id>/complete?space=` → 201 `{file}`, or 200
//      `{file, duplicate: true}` — or 202 `{status: "storing"}` when the site
//      needs longer than the ~100 s a request may take to keep a big file.
//   `GET uploads/<id>?space=` says how far it got (`status`: uploading,
//   storing, done with the file, or failed), after a 202 or a lost answer.
//   A 404 means the session ran out (24 h idle): it starts afresh, once, as
//   does a store that failed (the bytes didn't arrive whole).

/// What the site said a session is: as it starts, and when asked how far it got.
struct DriveUploadSession: Decodable, Equatable {
    let uploadId: String
    let received: Int
    let chunkBytes: Int
    var size: Int? = nil
    var expiresAt: String? = nil
}

/// How a session stands, when asked (`GET`). Every field is read leniently:
/// what is there depends on `status`.
struct DriveUploadStatus: Decodable, Equatable {
    /// "uploading", "storing", "done" or "failed"; missing from a site
    /// that stores as `complete` answers, which means "uploading".
    var status: String? = nil
    var received: Int? = nil
    var chunkBytes: Int? = nil
    /// `done`: the file, and whether these bytes were there already.
    var file: DriveFile? = nil
    var duplicate: Bool? = nil
    /// `failed`: why, in the site's words.
    var message: String? = nil
}

/// What a session starts with (the JSON body of step 1). `takenAt` is left
/// out when there is none.
struct DriveUploadSessionStart: Encodable, Equatable {
    let folder: String
    let filename: String
    let type: String
    let size: Int
    let sha256: String
    var takenAt: String? = nil
}

/// How far a big upload has got, kept with the job (and so across relaunches).
struct DriveChunkState: Codable, Equatable {
    /// What is sent next.
    enum Step: Codable, Equatable {
        /// Start a session.
        case create
        /// Send the chunk that starts here.
        case put(offset: Int)
        /// Ask the site how far it got.
        case status
        /// Every byte is there: ask the site to check and keep it.
        case complete
        /// The site is keeping it (a 202, or no answer from `complete`): ask
        /// again after `DriveChunks.pollDelay(polls)`. Kept with the job, so a
        /// relaunch goes on asking rather than sending the file again.
        case storing(polls: Int)
    }

    var step: Step = .create
    var uploadId: String? = nil
    /// Bytes the site has said it holds.
    var received: Int = 0
    var chunkBytes: Int = DriveChunks.chunkBytes
    /// Sessions started again after the site lost one (404).
    var restarts: Int = 0

    /// Where to pick up after a failure or a relaunch: ask how far the
    /// session got, or start one if there is none yet.
    var resumed: DriveChunkState {
        var next = self
        if case .storing = step, uploadId != nil { return next }
        next.step = uploadId == nil ? .create : .status
        return next
    }
}

/// What one answer means for a big upload.
enum DriveChunkResult: Equatable {
    /// Carry on with the state's next step. `progressed`: the site took more bytes.
    case next(DriveChunkState, progressed: Bool)
    /// On the site. `safe` exactly as for a single upload: a `complete` that
    /// answered 201, or a 200 that said `duplicate: true` (from `complete` or
    /// from the session's start) — the only answers that prove the bytes are held.
    case stored(fileId: String, duplicate: Bool, safe: Bool)
    /// Did not get there; tried again from `resume`.
    case failed(String, resume: DriveChunkState)
    /// The site said no and will say it again.
    case refused(String)
}

/// Which way a file goes up.
enum DriveUploadRoute: Equatable {
    /// One request, as always.
    case single
    /// A session, a chunk at a time.
    case chunked
    /// Too big for either: the sentence to say.
    case refused(String)
}

enum DriveChunks {
    /// 8 MiB: what the site asks for, until a session says otherwise.
    static let chunkBytes = 8_388_608
    /// A session the site lost is started again once in a row.
    static let maxRestarts = 1
    /// The chunk sizes this app will send: anything else is a misread answer.
    static let chunkRange = 65_536...67_108_864
    /// Asking how the keeping goes stops after this many (about an hour at
    /// 15 s), as a failure: the next go asks again.
    static let maxPolls = 240

    /// Seconds before asking again how the keeping goes: 3, 6, 9, 12, then 15.
    static func pollDelay(_ polls: Int) -> Int {
        min(3 + 3 * max(0, polls), 15)
    }

    // MARK: - Which way

    /// Single-shot up to `single`; a session above it, when the site has said
    /// it takes them (`large`, from the listing's `maxLargeUploadBytes`);
    /// refused over that, with the limit in GB.
    static func route(size: Int, single: Int, large: Int?) -> DriveUploadRoute {
        if size <= single { return .single }
        guard let large else {
            return .refused(DriveLogic.tooLarge(size, limit: single) ?? "That file is too big for Drive.")
        }
        if size > large {
            return .refused("That is \(gigabytes(size, up: true)) — the most Drive can take is \(gigabytes(large)).")
        }
        return .chunked
    }

    /// "4 GB", "1.5 GB", "0.8 GB": 1024³ bytes to a GB, as the site counts.
    /// A limit rounds down and a file's size up, so a file over the limit
    /// never reads as the same number.
    static func gigabytes(_ bytes: Int, up: Bool = false) -> String {
        let value = Double(bytes) / 1_073_741_824
        let tenths = (value * 10).rounded(up ? .up : .down) / 10
        let shown = tenths >= 0.1 ? tenths : 0.1
        if shown == shown.rounded() { return "\(Int(shown)) GB" }
        return String(format: "%.1f GB", shown)
    }

    // MARK: - The plan

    /// The bytes in the chunk that starts at `offset`: a full chunk, the
    /// rest of the file for the last, nothing past the end.
    static func length(offset: Int, size: Int, chunkBytes: Int) -> Int {
        guard offset >= 0, offset < size, chunkBytes > 0 else { return 0 }
        return min(chunkBytes, size - offset)
    }

    /// Every chunk's offset from `from` (the site's `received`) to the end.
    static func offsets(size: Int, chunkBytes: Int, from: Int = 0) -> [Int] {
        guard chunkBytes > 0, size > 0 else { return [] }
        return Array(stride(from: max(0, from), to: size, by: chunkBytes))
    }

    /// What follows the site holding `received` bytes.
    static func after(_ state: DriveChunkState, received: Int, size: Int) -> DriveChunkState {
        var next = state
        next.received = min(max(0, received), size)
        next.step = next.received >= size ? .complete : .put(offset: next.received)
        return next
    }

    // MARK: - What an answer means

    private struct Reply: Decodable {
        var error: String? = nil
        var message: String? = nil
        var received: Int? = nil
    }

    /// The answer to `state.step`. `size` is the file's.
    static func answer(_ state: DriveChunkState, size: Int, status: Int?, body: Data?,
                       transportError: String?) -> DriveChunkResult {
        let resume = state.resumed
        // No answer to `complete`, or the edge cutting it off (524 and the
        // like): the site may well be keeping it. Ask, rather than send again.
        if state.step == .complete, status == nil || status == 408 || (status ?? 0) >= 500 {
            return .next(storing(state, size: size), progressed: false)
        }
        guard let status else {
            return .failed(transportError ?? "Couldn't reach the site.", resume: resume)
        }
        let reply = body.flatMap { try? JSONDecoder().decode(Reply.self, from: $0) }
        let words = (reply?.error?.isEmpty == false ? reply?.error : nil)
            ?? (reply?.message?.isEmpty == false ? reply?.message : nil)

        // The same for every step.
        switch status {
        case 401:
            return .failed("This phone needs connecting again.", resume: resume)
        case 408, 429, 500...:
            // 507 is here: the site is short of room for now, not for ever.
            return .failed(words ?? "The site was busy.", resume: resume)
        case 413:
            return .refused(words ?? "That file is too big for Drive.")
        default:
            break
        }

        switch state.step {
        case .create:
            if status == 200 {
                // These bytes are already in the space: nothing to send.
                return stored(status: status, body: body, resume: resume)
            }
            guard status == 201 else {
                return .refused(words ?? "The site wouldn't take that (\(status)).")
            }
            guard let body, let session = try? JSONDecoder().decode(DriveUploadSession.self, from: body),
                  validId(session.uploadId), chunkRange.contains(session.chunkBytes) else {
                return .failed("The site's answer couldn't be read.", resume: resume)
            }
            var next = state
            next.uploadId = session.uploadId
            next.chunkBytes = session.chunkBytes
            return .next(after(next, received: session.received, size: size), progressed: session.received > 0)

        case .put(let offset):
            switch status {
            case 200..<300:
                guard let received = reply?.received else {
                    return .failed("The site's answer couldn't be read.", resume: resume)
                }
                guard received > offset else {
                    return .failed("The site didn't keep that piece.", resume: resume)
                }
                return .next(after(state, received: received, size: size), progressed: true)
            case 409:
                guard let received = reply?.received else { return .failed(words ?? "The site was busy.", resume: resume) }
                // Another send to this session is still going: wait, then ask.
                if received == offset { return .failed(words ?? "The site was busy.", resume: resume) }
                return .next(after(state, received: received, size: size), progressed: received > state.received)
            case 404:
                return lost(state)
            default:
                return .refused(words ?? "The site wouldn't take that (\(status)).")
            }

        case .status, .storing:
            var polls = 0
            if case .storing(let n) = state.step { polls = n + 1 }
            switch status {
            case 200..<300:
                guard let body, let reply = try? JSONDecoder().decode(DriveUploadStatus.self, from: body) else {
                    return .failed("The site's answer couldn't be read.", resume: resume)
                }
                switch reply.status ?? "uploading" {
                case "done":
                    // Done WITH a file is the proof; done without one is not.
                    guard let file = reply.file else { return .failed("The site's answer couldn't be read.", resume: resume) }
                    return .stored(fileId: file.id, duplicate: reply.duplicate == true, safe: true)
                case "storing":
                    guard polls < maxPolls else {
                        return .failed("The site is still keeping it. It'll be asked again.", resume: resume)
                    }
                    var next = state
                    next.received = size
                    next.step = .storing(polls: polls)
                    return .next(next, progressed: false)
                case "failed":
                    return restart(state, refusal: reply.message ?? words ?? "The file didn't arrive whole. Add it again.")
                default:
                    guard let received = reply.received else {
                        return .failed("The site's answer couldn't be read.", resume: resume)
                    }
                    var next = state
                    if let chunk = reply.chunkBytes, chunkRange.contains(chunk) { next.chunkBytes = chunk }
                    return .next(after(next, received: received, size: size), progressed: received > state.received)
                }
            case 404:
                return lost(state)
            default:
                return .refused(words ?? "The site wouldn't take that (\(status)).")
            }

        case .complete:
            switch status {
            case 202:
                // Every byte is there and the site is keeping it: ask how it goes.
                return .next(storing(state, size: size), progressed: false)
            case 200..<300:
                return stored(status: status, body: body, resume: resume)
            case 409:
                // Not every byte is there after all: carry on from where it is.
                // With all of them there, it is already keeping it.
                if let received = reply?.received, received < size {
                    return .next(after(state, received: received, size: size), progressed: false)
                }
                return .next(storing(state, size: size), progressed: false)
            case 404:
                return lost(state)
            case 422:
                // The bytes the site put together aren't these: it has thrown
                // the session away. Once more from the start, then stop.
                return restart(state, refusal: words ?? "The file didn't arrive whole. Add it again.")
            default:
                return .refused(words ?? "The site wouldn't take that (\(status)).")
            }
        }
    }

    /// Asking how the keeping goes, from the first ask.
    private static func storing(_ state: DriveChunkState, size: Int) -> DriveChunkState {
        var next = state
        next.received = size
        next.step = .storing(polls: 0)
        return next
    }

    /// The site threw the session away (a store that failed, a hash that
    /// didn't match): a fresh one the first time, then refused.
    private static func restart(_ state: DriveChunkState, refusal: String) -> DriveChunkResult {
        guard state.restarts < maxRestarts else { return .refused(refusal) }
        return .next(DriveChunkState(chunkBytes: state.chunkBytes, restarts: state.restarts + 1), progressed: false)
    }

    /// The session ran out on the site: a new one at once, the first time.
    private static func lost(_ state: DriveChunkState) -> DriveChunkResult {
        let fresh = DriveChunkState(chunkBytes: state.chunkBytes, restarts: state.restarts + 1)
        guard state.restarts < maxRestarts else {
            // Again: the next go (the queue's own, or Try again) starts afresh.
            return .failed("The upload ran out of time on the site.",
                           resume: DriveChunkState(chunkBytes: state.chunkBytes, restarts: state.restarts))
        }
        return .next(fresh, progressed: false)
    }

    /// A file on the site: safe only for a 201, or a 200 that said duplicate.
    private static func stored(status: Int, body: Data?, resume: DriveChunkState) -> DriveChunkResult {
        guard let body, let reply = try? JSONDecoder().decode(DriveUploadReply.self, from: body) else {
            return .failed("The site's answer couldn't be read.", resume: resume)
        }
        let duplicate = reply.duplicate == true
        let safe = status == 201 || (status == 200 && duplicate)
        return .stored(fileId: reply.file.id, duplicate: duplicate, safe: safe)
    }

    /// 32 lowercase hex, as the site makes them: never a path of its own.
    static func validId(_ id: String) -> Bool {
        id.count == 32 && id.unicodeScalars.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    // MARK: - Requests

    /// The path and method for a step. Nil for a step that needs a session it has not got.
    static func request(_ state: DriveChunkState, space: DriveSpace) -> (path: String, method: String)? {
        let base = "api/native/drive/uploads"
        let query = "space=\(space.rawValue)"
        switch state.step {
        case .create:
            return ("\(base)?\(query)", "POST")
        case .put(let offset):
            guard let id = state.uploadId, validId(id) else { return nil }
            return ("\(base)/\(id)?\(query)&offset=\(offset)", "PUT")
        case .status, .storing:
            guard let id = state.uploadId, validId(id) else { return nil }
            return ("\(base)/\(id)?\(query)", "GET")
        case .complete:
            guard let id = state.uploadId, validId(id) else { return nil }
            return ("\(base)/\(id)/complete?\(query)", "POST")
        }
    }

    /// A session's DELETE, to give back the site's room when a big upload is given up.
    static func cancelPath(_ uploadId: String, space: DriveSpace) -> String? {
        guard validId(uploadId) else { return nil }
        return "api/native/drive/uploads/\(uploadId)?space=\(space.rawValue)"
    }

    // MARK: - Background tasks

    /// What a background task is for, written on it (`taskDescription`), so
    /// an answer that arrives after a relaunch is matched to its job and
    /// step. A single upload's task carries the job id alone, as it always has.
    static func taskDescription(job: String, step: DriveChunkState.Step) -> String {
        switch step {
        case .create: return "\(job)|create"
        case .put(let offset): return "\(job)|put|\(offset)"
        case .status: return "\(job)|status"
        case .complete: return "\(job)|complete"
        case .storing(let polls): return "\(job)|storing|\(polls)"
        }
    }

    /// The job id, and the step when it was a big upload's.
    static func parseTask(_ description: String) -> (job: String, step: DriveChunkState.Step?) {
        let parts = description.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard parts.count > 1 else { return (description, nil) }
        switch parts[1] {
        case "create": return (parts[0], .create)
        case "status": return (parts[0], .status)
        case "complete": return (parts[0], .complete)
        case "put":
            if parts.count == 3, let offset = Int(parts[2]) { return (parts[0], .put(offset: offset)) }
            return (parts[0], nil)
        case "storing":
            if parts.count == 3, let polls = Int(parts[2]) { return (parts[0], .storing(polls: polls)) }
            return (parts[0], nil)
        default: return (parts[0], nil)
        }
    }
}
