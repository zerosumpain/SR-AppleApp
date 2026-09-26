import Foundation
import Combine

/// /health, on the phone.
///
/// One endpoint, because the four figures come from one derivation in SR-Health
/// and splitting them across four calls on a mobile connection buys nothing but
/// four chances to fail differently.
@MainActor
final class HealthStore: ObservableObject {
    @Published private(set) var summary: HealthSummary?
    @Published private(set) var loading = false
    @Published private(set) var unavailable = false
    @Published var message: String?

    private let client = SiteClient.shared

    func load(fresh: Bool = false) async {
        guard AccessStore.ownerSite else { return }
        guard !loading else { return }
        loading = true
        defer { loading = false }
        do {
            // Annotated, and assigned in two steps. Assigning straight into the
            // optional property makes `T` infer as `HealthSummary?`, which asks
            // JSONDecoder to decode an Optional — it works, and it is one
            // refactor away from silently decoding `null` as success.
            let payload: HealthSummary = try await client.send(
                "api/native/health/summary\(fresh ? "?fresh=1" : "")"
            )
            summary = payload
            unavailable = false
            message = nil
        } catch SiteError.unpaired {
            summary = nil
        } catch {
            // Health is a different container behind its own gateway. "It is not
            // answering" is a state with its own screen, not a red banner over
            // four dashes — four dashes read as "you did nothing yesterday".
            if summary == nil { unavailable = true }
            message = error.localizedDescription
        }
    }
}
