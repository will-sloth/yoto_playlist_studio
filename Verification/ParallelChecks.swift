import Foundation

@main struct ParallelChecks {
    @MainActor static func main() async {
        var active = 0, peak = 0
        var results = [Int?](repeating: nil, count: 7)
        var completed: [Int] = []
        await ParallelAudio.run(indices: Array(results.indices), limit: 3) { index in
            active += 1; peak = max(peak, active)
            defer { active -= 1 }
            try? await Task.sleep(nanoseconds: UInt64(index == 0 ? 80 : 5) * 1_000_000)
            results[index] = index; completed.append(index)
        }
        precondition(peak == 3 && active == 0)
        precondition(results.compactMap { $0 } == Array(0..<7))
        precondition(completed.first != 0)
        print("PASS: three operations overlap, concurrency stays bounded, out-of-order completion preserves queue positions")
        var attempts = [Int](repeating: 0, count: 5)
        var ready = Set<Int>()
        func attempt(_ indices: [Int]) async {
            await ParallelAudio.run(indices: indices, limit: 2) { index in
                attempts[index] += 1
                try? await Task.sleep(nanoseconds: 1_000_000)
                if index != 2 || attempts[index] > 1 { ready.insert(index) }
            }
        }
        await attempt(Array(0..<5))
        precondition(ready.count == 4)
        await attempt((0..<5).filter { !ready.contains($0) })
        precondition(ready.count == 5 && attempts == [1, 1, 2, 1, 1])
        print("PASS: one failure does not prevent sibling completion; retry can reuse successful operations")
        var started = 0
        let task = Task { @MainActor in
            await ParallelAudio.run(indices: Array(0..<20), limit: 2) { _ in
                started += 1
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
        while started < 2 { await Task.yield() }
        task.cancel(); await task.value
        precondition(started == 2)
        print("PASS: cancellation reaches active work and does not start queued operations")
        var serialActive = 0, serialPeak = 0
        await ParallelAudio.run(indices: [0,1,2], limit: 1) { _ in
            serialActive += 1; serialPeak = max(serialPeak, serialActive)
            try? await Task.sleep(nanoseconds: 1_000_000)
            serialActive -= 1
        }
        precondition(serialPeak == 1)
        print("PASS: single-track setting remains sequential")
    }
}
