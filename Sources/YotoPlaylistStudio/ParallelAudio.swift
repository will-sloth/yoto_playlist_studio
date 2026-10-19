import Foundation

@MainActor
enum ParallelAudio {
    static func run(indices: [Int], limit: Int, operation: @escaping @MainActor (Int) async -> Void) async {
        guard !Task.isCancelled else { return }
        await withTaskGroup(of: Void.self) { group in
            var pending = indices.makeIterator()
            for _ in 0..<max(1, min(limit, indices.count)) {
                guard let index = pending.next(), !Task.isCancelled else { break }
                group.addTask { @MainActor in
                    guard !Task.isCancelled else { return }
                    await operation(index)
                }
            }
            while await group.next() != nil {
                guard !Task.isCancelled else { group.cancelAll(); continue }
                if let index = pending.next() {
                    group.addTask { @MainActor in
                        guard !Task.isCancelled else { return }
                        await operation(index)
                    }
                }
            }
        }
    }
}
