import Foundation
import Combine

@MainActor final class CommissionStore: ObservableObject {
    static let shared = CommissionStore()
    @Published private(set) var commissions: [DaydreamCommission] = []
    @Published private(set) var enabled = false
    @Published private(set) var busy = false
    @Published private(set) var error: String?
    @Published var destination: CommissionDestination?
    private let client = SiteClient.shared

    func clear() { commissions = []; enabled = false; error = nil; destination = nil }

    func load() async {
        guard AccessStore.ownerSite else { clear(); return }
        do {
            let feed: CommissionFeed = try await client.send("api/native/daydream/commissions")
            guard AccessStore.ownerSite else { clear(); return }
            enabled = feed.enabled; commissions = feed.commissions; error = nil
        } catch is CancellationError {
        } catch { self.error = "Improvement history could not be refreshed. Your decisions are retained." }
    }
    func load(id: String) async {
        guard AccessStore.ownerSite else { clear(); return }
        guard UUID(uuidString: id) != nil else { return }
        do {
            let reply: CommissionReply = try await client.send("api/native/daydream/commissions?id=\(id)")
            keep(reply.commission); error = nil
        } catch is CancellationError {
        } catch { self.error = "This improvement could not be loaded. Open Daydream to try again." }
    }
    func prepare(thoughtId: String) async {
        guard AccessStore.ownerSite, !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let body = try JSONSerialization.data(withJSONObject: ["action": "prepare", "thoughtId": thoughtId])
            let data = try await client.post("api/native/daydream/commissions", body: body)
            let reply = try JSONDecoder().decode(CommissionReply.self, from: data)
            keep(reply.commission); destination = CommissionDestination(id: reply.commission.id)
        } catch { self.error = error.localizedDescription }
    }
    func decide(_ commission: DaydreamCommission, decision: String) async {
        guard AccessStore.ownerSite, !busy else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let body = try JSONEncoder().encode(CommissionDecisionRequest(commission, decision: decision))
            let data = try await client.post("api/native/daydream/commissions", body: body)
            keep(try JSONDecoder().decode(CommissionReply.self, from: data).commission)
        } catch {
            self.error = error.localizedDescription
            // A lost response may follow a committed decision. Fetch before retry.
            let message = self.error
            await load(id: commission.id)
            self.error = message
        }
    }
    private func keep(_ commission: DaydreamCommission) {
        guard AccessStore.ownerSite else { clear(); return }
        commissions.removeAll { $0.id == commission.id }
        commissions.append(commission)
        commissions.sort { $0.updatedAt > $1.updatedAt }
    }
}
