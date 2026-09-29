import Foundation
import HealthKit

/// HealthKit can finish after cancellation or a timeout. Exactly one outcome
/// resumes the awaiting task; stopping a query never strands its continuation.
final class HealthQueryResult<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?
    private var finished = false
    private var pending: Result<Value, Error>?
    private var query: HKQuery?
    private var store: HKHealthStore?
    private var timeout: DispatchWorkItem?

    func attach(_ continuation: CheckedContinuation<Value, Error>) {
        lock.lock()
        if let pending { lock.unlock(); continuation.resume(with: pending); return }
        self.continuation = continuation
        lock.unlock()
    }
    func execute(_ query: HKQuery, in store: HKHealthStore, until deadline: Date) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        self.query = query; self.store = store
        let timer = DispatchWorkItem { [weak self] in self?.resume(throwing: CompanionError.message("Apple Health took too long. Collection will resume from saved progress.")) }
        timeout = timer
        // Register execution while locked: cancellation cannot stop a query
        // before it has started and then leave it running afterwards.
        store.execute(query)
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + max(0.05, min(8, deadline.timeIntervalSinceNow)), execute: timer)
    }
    func resume(returning value: Value) { complete(.success(value)) }
    func resume(throwing error: Error) { complete(.failure(error)) }
    func cancel() { complete(.failure(CancellationError())) }
    private func complete(_ result: Result<Value, Error>) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true; pending = result
        let continuation = continuation, query = query, store = store, timeout = timeout
        self.continuation = nil; self.query = nil; self.store = nil; self.timeout = nil
        lock.unlock()
        timeout?.cancel()
        if let query { store?.stop(query) }
        continuation?.resume(with: result)
    }
}

@MainActor func boundedHealthQuery<Value>(until deadline: Date, _ build: (HealthQueryResult<Value>) -> Void) async throws -> Value {
    try Task.checkCancellation()
    guard deadline > Date() else { throw CancellationError() }
    let result = HealthQueryResult<Value>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            result.attach(continuation)
            build(result)
        }
    } onCancel: { result.cancel() }
}
