import Foundation
import Network
import FluidAudio

// Who spoke when, on the phone: FluidAudio's pyannote-derived CoreML models
// (Apache-2.0), so no audio leaves the phone for this step.
//
// Behind `CaptureDiarizing`, with one speaker as the answer whenever the
// models are not there — not downloaded yet, on mobile data with the owner
// not having said yes, a download that failed, or a recording too long to
// hold in memory. A capture never waits on, or fails for, diarization.
//
// The models (~35 MB, from Hugging Face) download on FIRST USE, on Wi-Fi —
// Settings → Captures says so and has a button to do it now. Never over
// mobile data unless the owner turned that on, or confirmed it there.

protocol CaptureDiarizing {
    /// The voices' segments, or nil for "one speaker".
    func diarize(_ url: URL, duration: TimeInterval) async -> [CaptureVoiceSegment]?
}

/// The fallback: everybody is S1.
struct SingleSpeakerDiarizer: CaptureDiarizing {
    func diarize(_ url: URL, duration: TimeInterval) async -> [CaptureVoiceSegment]? { nil }
}

/// The speaker models' state, for Settings → Captures.
@MainActor
final class CaptureModelsStore: ObservableObject {
    static let shared = CaptureModelsStore()

    enum Phase: Equatable {
        case absent
        /// A capture wanted them on mobile data; they wait for Wi-Fi.
        case waitingForWiFi
        case downloading
        case ready
        case failed(String)
    }

    @Published private(set) var phase: Phase

    nonisolated static let readyKey = "captures.modelsReady"
    /// Roughly what the download costs, said before it happens.
    nonisolated static let sizeLine = "about 35 MB"

    private init() {
        phase = UserDefaults.standard.bool(forKey: Self.readyKey) ? .ready : .absent
    }

    func set(_ phase: Phase) {
        self.phase = phase
        if phase == .ready { UserDefaults.standard.set(true, forKey: Self.readyKey) }
        if phase == .absent { UserDefaults.standard.set(false, forKey: Self.readyKey) }
    }

    /// Settings' "Download now". `overCellular`: the owner confirmed using
    /// mobile data for it.
    func download(overCellular: Bool) async {
        _ = await CaptureDiarization.shared.models(trigger: overCellular ? .confirmedCellular : .owner)
    }

    /// Settings' "Remove": the models go, and captures are one speaker until
    /// they are downloaded again.
    func remove() async {
        await CaptureDiarization.shared.forget()
        set(.absent)
    }
}

/// FluidAudio, held in one actor: the models load once per launch and every
/// pass runs off the main thread.
actor CaptureDiarization: CaptureDiarizing {
    static let shared = CaptureDiarization()

    /// Longer than this is not diarized: 90 minutes at 16 kHz is ~350 MB of
    /// samples in memory, which is as much as a phone should be asked for.
    static let maxDuration: TimeInterval = 90 * 60

    enum Trigger { case capture, owner, confirmedCellular }

    private var loaded: DiarizerModels?

    func diarize(_ url: URL, duration: TimeInterval) async -> [CaptureVoiceSegment]? {
        guard duration <= Self.maxDuration, let models = await models(trigger: .capture) else { return nil }
        do {
            let samples = try AudioConverter().resampleAudioFile(url)
            guard !samples.isEmpty else { return nil }
            let manager = DiarizerManager()
            manager.initialize(models: models)
            defer { manager.cleanup() }
            let result = try manager.performCompleteDiarization(samples, sampleRate: 16_000)
            let segments = result.segments.map {
                CaptureVoiceSegment(
                    speaker: $0.speakerId,
                    start: Double($0.startTimeSeconds),
                    end: Double($0.endTimeSeconds),
                    embedding: $0.embedding
                )
            }
            return segments.isEmpty ? nil : segments
        } catch {
            return nil
        }
    }

    /// One voice's embedding, for enrolment. Asked by the owner, so it may
    /// download the models — on Wi-Fi, or with mobile data allowed.
    func embedding(_ url: URL) async -> [Float]? {
        guard let models = await models(trigger: .owner) else { return nil }
        do {
            let samples = try AudioConverter().resampleAudioFile(url)
            guard samples.count > 16_000 * 3 else { return nil }
            let manager = DiarizerManager()
            manager.initialize(models: models)
            defer { manager.cleanup() }
            let embedding = try manager.extractSpeakerEmbedding(from: samples)
            return embedding.isEmpty ? nil : embedding
        } catch {
            return nil
        }
    }

    /// The models, loading or downloading them if the network and the
    /// owner's settings allow.
    func models(trigger: Trigger) async -> DiarizerModels? {
        if let loaded { return loaded }
        let alreadyHere = UserDefaults.standard.bool(forKey: CaptureModelsStore.readyKey)
        if !alreadyHere {
            let costly = await CaptureNetwork.isCostly()
            let cellularOK = trigger == .confirmedCellular || CaptureSettings.modelsOnCellular
            if costly && !cellularOK {
                await MainActor.run { CaptureModelsStore.shared.set(.waitingForWiFi) }
                return nil
            }
            await MainActor.run { CaptureModelsStore.shared.set(.downloading) }
        }
        do {
            // Loads from the phone when they are there; fetches them otherwise.
            let models = try await DiarizerModels.downloadIfNeeded()
            loaded = models
            await MainActor.run { CaptureModelsStore.shared.set(.ready) }
            return models
        } catch {
            let message = error.localizedDescription
            await MainActor.run { CaptureModelsStore.shared.set(.failed(message)) }
            return nil
        }
    }

    func forget() {
        loaded = nil
        try? FileManager.default.removeItem(at: DiarizerModels.defaultModelsDirectory())
    }
}

enum CaptureNetwork {
    /// Mobile data, Low Data Mode, or no network: not for a 35 MB download.
    static func isCostly() async -> Bool {
        await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let monitor = NWPathMonitor()
            let once = CaptureOnce()
            monitor.pathUpdateHandler = { path in
                once.run {
                    continuation.resume(returning: path.status != .satisfied || path.isExpensive || path.isConstrained)
                }
                monitor.cancel()
            }
            monitor.start(queue: DispatchQueue(label: "sr.captures.network"))
        }
    }
}
