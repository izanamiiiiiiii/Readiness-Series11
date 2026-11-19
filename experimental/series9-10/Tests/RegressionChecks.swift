import Foundation

enum RegressionChecks {
    static func run() async throws -> Int {
        var count = 0
        func check(_ value: Bool, _ label: String) {
            precondition(value, label); count += 1; print("PASS: \(label)")
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/Santiago")!
        let now = Date()
        let day = cal.startOfDay(for: now)
        func night(_ offset: Int, rmssd: Double? = 45, sleep: Double? = 7) -> OvernightSummary {
            OvernightSummary(morningDate: cal.date(byAdding: .day, value: offset, to: day)!, rmssdMs: rmssd, restingHRBpm: 60, sleepDurationHours: sleep)
        }
        let history = [-3, -2, -1].map { night($0) }
        check(RobustReadinessEngine.evaluate(history: history, today: night(0)).finalScore != nil, "Qualified nights calculate")
        check(RobustReadinessEngine.evaluate(history: history, today: night(-1)).finalScore == nil, "Yesterday is never current")
        check(RobustReadinessEngine.evaluate(history: history, today: night(0, rmssd: nil)).finalScore == nil, "Missing RMSSD has no score")
        check(RobustReadinessEngine.evaluate(history: history, today: night(0, rmssd: .nan)).finalScore == nil, "NaN has no score")
        check(RobustReadinessEngine.evaluate(history: history, today: night(0, sleep: 2)).finalScore == nil, "Short sleep rejected")
        check(RobustReadinessEngine.evaluate(history: history, today: night(0, sleep: nil)).finalScore == nil, "Unlinked sleep rejected")
        check(RobustReadinessEngine.evaluate(history: [night(-1),night(-1),night(-1)], today: night(0)).finalScore == nil, "Duplicate days cannot calibrate")
        check(RobustReadinessEngine.evaluate(history: [-40,-39,-38].map { night($0) }, today: night(0)).finalScore == nil, "Old baseline cannot calibrate")
        check(RobustReadinessEngine.evaluate(history: [night(1),night(2),night(3)], today: night(0)).finalScore == nil, "Future baseline rejected")
        check(!NightQuality.trustedSource(product: "Watch7,18", bundle: "com.apple.health.abc", manual: true), "Manual input rejected")
        check(!NightQuality.trustedSource(product: "Watch7,18", bundle: "org.example", manual: false), "Third party rejected")
        check(!NightQuality.trustedSource(product: "iPhone", bundle: "com.apple.health.abc", manual: false), "Phone source rejected")
        check(NightQuality.trustedSource(product: "watch7,18", bundle: "com.apple.health.abc", manual: false), "Watch source case supported")
        let yesterday = cal.date(byAdding: .day, value: -1, to: day)!
        let start = cal.date(bySettingHour: 23, minute: 0, second: 0, of: yesterday)!
        let end = cal.date(bySettingHour: 7, minute: 0, second: 0, of: day)!
        let segments = NightQuality.nights([DateInterval(start: start, end: end), DateInterval(start: start.addingTimeInterval(3600), end: end)], calendar: cal)[day]!
        check(segments.count == 1 && segments[0].duration == end.timeIntervalSince(start), "Midnight and overlapping stages merged by actual helper")
        check(!NightQuality.contains(start: end.addingTimeInterval(3600), end: end.addingTimeInterval(3660), segments: segments), "Awake heartbeat excluded")
        check(!NightQuality.contains(start: start.addingTimeInterval(-30), end: start.addingTimeInterval(30), segments: segments), "Partial overlap excluded")
        let fragmented = [DateInterval(start: start, end: start.addingTimeInterval(120)),DateInterval(start: start.addingTimeInterval(180), end: end)]
        check(!NightQuality.contains(start: start.addingTimeInterval(60), end: start.addingTimeInterval(240), segments: fragmented), "Series crossing wake gap excluded")
        var acc = SafeRRAccumulator(); var time = 0.0
        acc.append(time: time, precededByGap: false)
        for i in 0..<100 { time += i.isMultiple(of: 2) ? 0.8 : 0.85; acc.append(time: time, precededByGap: false) }
        check(abs((acc.rmssdMilliseconds ?? 0) - 50) < 0.001, "Known RR sequence gives 50 ms")
        var short = SafeRRAccumulator()
        for i in 0..<12 { short.append(time: Double(i)*0.8, precededByGap: false) }
        check(short.rmssdMilliseconds == nil, "Very short series rejected")
        acc.append(time: .nan, precededByGap: false)
        check(acc.rejectedIntervalsCount == 1, "Nonfinite beat resets accumulator")
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = ReadinessStorageCoordinator(customDirectory: dir)
        let id = UUID()
        await store.store(entry: HeartbeatCacheEntry(sampleUUID: id, endDate: now, rmssdMs: 50, validDifferencesCount: 99))
        let reopened = ReadinessStorageCoordinator(customDirectory: dir)
        check(await reopened.getCachedRMSSD(for: id) == 50, "Cache persists across new coordinator")
        let old = UUID()
        await store.store(entry: HeartbeatCacheEntry(sampleUUID: old, endDate: now.addingTimeInterval(-40*86400), rmssdMs: 40, validDifferencesCount: 99))
        await store.pruneOldEntries()
        check(await store.getCachedRMSSD(for: old) == nil, "Old cache pruned")
        await store.saveSnapshot(CachedReadinessSnapshot(score: 80, confidence: 0.5, formulaVersion: RobustReadinessEngine.formulaVersion, calculatedAt: now, baselineDaysUsed: 3))
        check(await reopened.loadSnapshot()?.score == 80, "Snapshot persists to disk")
        await store.clearSnapshot()
        check(await reopened.loadSnapshot() == nil, "Invalid current data can remove snapshot")
        try Data("corrupt".utf8).write(to: dir.appendingPathComponent("heartbeat_series_cache_v4.json"))
        let corrupt = ReadinessStorageCoordinator(customDirectory: dir)
        check(await corrupt.getCachedRMSSD(for: id) == nil, "Corrupt cache safely recomputes")
        print("\(count) regression checks passed"); return count
    }
}
