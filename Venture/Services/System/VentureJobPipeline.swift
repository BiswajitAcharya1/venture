import Foundation

actor VentureJobPipeline {
    private var jobs: [String: Task<Void, Never>] = [:]

    func replace(
        id: String,
        priority: TaskPriority = .userInitiated,
        operation: @Sendable @escaping () async -> Void
    ) {
        jobs[id]?.cancel()
        let task = Task(priority: priority) { await operation() }
        jobs[id] = task
    }

    func cancel(id: String) {
        jobs[id]?.cancel()
        jobs[id] = nil
    }

    func cancelAll() {
        jobs.values.forEach { $0.cancel() }
        jobs.removeAll()
    }
}
