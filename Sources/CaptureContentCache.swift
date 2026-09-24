import Foundation

/// Coalesces capture-content requests while loading and reuses a successful
/// result briefly. Failures are evicted so the next capture can retry.
@MainActor
final class CaptureContentCache<Value> {
    private struct Entry {
        let token: UUID
        let task: Task<Value, Error>
        var fetchedAt: Date?
    }
    private var entry: Entry?
    private let lifetime: TimeInterval
    private let clock: () -> Date

    init(lifetime: TimeInterval, clock: @escaping () -> Date = Date.init) {
        self.lifetime = lifetime
        self.clock = clock
    }

    func task(load: @escaping () async throws -> Value) -> Task<Value, Error> {
        if let entry {
            if entry.fetchedAt == nil { return entry.task }
            if let date = entry.fetchedAt, clock().timeIntervalSince(date) < lifetime { return entry.task }
        }
        let token = UUID()
        let task = Task { [weak self] in
            do {
                let value = try await load()
                if self?.entry?.token == token { self?.entry?.fetchedAt = self?.clock() }
                return value
            } catch {
                if self?.entry?.token == token { self?.entry = nil }
                throw error
            }
        }
        entry = Entry(token: token, task: task, fetchedAt: nil)
        return task
    }
}
