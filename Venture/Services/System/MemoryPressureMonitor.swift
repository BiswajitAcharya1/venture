import Foundation
import os

final class MemoryPressureMonitor {
    static let shared = MemoryPressureMonitor()

    private let queue = DispatchQueue(label: "com.venture.memory-pressure", qos: .utility)
    private var source: DispatchSourceMemoryPressure?
    private var handlers: [(MemoryPressureLevel) -> Void] = []
    private let logger = Logger(subsystem: "com.venture", category: "memory")

    private init() {
        setupMonitor()
    }

    private func setupMonitor() {
        source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: queue)
        source?.setEventHandler { [weak self] in
            guard let self, let event = self.source?.data else { return }
            let level = MemoryPressureLevel(from: event)
            self.logger.warning("Memory pressure: \(level.description)")
            self.notify(level: level)
        }
        source?.resume()
    }

    func addHandler(_ handler: @escaping (MemoryPressureLevel) -> Void) {
        queue.async { [weak self] in
            self?.handlers.append(handler)
        }
    }

    private func notify(level: MemoryPressureLevel) {
        handlers.forEach { $0(level) }
    }

    deinit {
        source?.cancel()
    }
}

enum MemoryPressureLevel: Sendable {
    case normal
    case warning
    case critical

    init(from event: DispatchSource.MemoryPressureEvent) {
        if event.contains(.critical) { self = .critical }
        else if event.contains(.warning) { self = .warning }
        else { self = .normal }
    }

    var description: String {
        switch self {
        case .normal: "normal"
        case .warning: "warning"
        case .critical: "critical"
        }
    }
}

protocol MemoryPressureResponding: AnyObject {
    func handleMemoryPressure(_ level: MemoryPressureLevel)
}

extension MemoryPressureResponding {
    func registerForMemoryPressure() {
        MemoryPressureMonitor.shared.addHandler { [weak self] level in
            Task { @MainActor in
                self?.handleMemoryPressure(level)
            }
        }
    }
}