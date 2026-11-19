import Foundation
import HealthKit
import os

struct FitnessSnapshot: Sendable {
    let evaluatedAt: Date
    let timeZoneIdentifier: String
    let activity: FitnessActivityResult
}

enum FitnessValueStore {
    private static let state = OSAllocatedUnfairLock<FitnessSnapshot?>(initialState: nil)
    static func publish(_ result: FitnessActivityResult?, now: Date, calendar: Calendar) {
        state.withLock { $0 = result.map { FitnessSnapshot(evaluatedAt: now, timeZoneIdentifier: calendar.timeZone.identifier, activity: $0) } }
    }
    static func current(now: Date = Date(), calendar: Calendar = .current) -> FitnessActivityResult? {
        state.withLock { snapshot in
            guard let snapshot, snapshot.timeZoneIdentifier == calendar.timeZone.identifier,
                  calendar.isDate(snapshot.evaluatedAt, inSameDayAs: now),
                  (0...3600).contains(now.timeIntervalSince(snapshot.evaluatedAt)) else { return nil }
            return snapshot.activity
        }
    }
}

@MainActor final class FitnessSummaryReader {
    static let shared = FitnessSummaryReader()
    private let store = HKHealthStore()
    private var query: HKActivitySummaryQuery?
    private var observers: [NSObjectProtocol] = []
    private var refreshTimer: Timer?

    func start() {
        Self.writeStatus("start", available: HKHealthStore.isHealthDataAvailable())
        guard query == nil, HKHealthStore.isHealthDataAvailable() else { return }
        for notification in [NSNotification.Name.NSCalendarDayChanged, NSNotification.Name.NSSystemTimeZoneDidChange] {
            observers.append(NotificationCenter.default.addObserver(forName: notification, object: nil, queue: .main) { _ in
                Task { @MainActor in FitnessSummaryReader.shared.reload() }
            })
        }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { _ in
            Task { @MainActor in FitnessSummaryReader.shared.reload() }
        }
        reload()
    }

    func reload() {
        if let query { store.stop(query) }
        let now = Date(), calendar = Calendar.current
        FitnessValueStore.publish(nil, now: now, calendar: calendar)
        guard let start = calendar.date(byAdding: .day, value: -28, to: now) else { return }
        let startParts = calendar.dateComponents([.calendar, .era, .year, .month, .day], from: start)
        let endParts = calendar.dateComponents([.calendar, .era, .year, .month, .day], from: now)
        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: startParts, end: endParts)
        let activeQuery = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
            Self.consume(summaries, error: error, calendar: calendar)
        }
        activeQuery.updateHandler = { _, _, _ in
            // An update may contain only changed days. Requery the full window.
            Task { @MainActor in FitnessSummaryReader.shared.reload() }
        }
        query = activeQuery
        // Authorization is owned by the containing Readiness app. No new permissions or writes here.
        Self.writeStatus("queryStarted", available: true)
        store.execute(activeQuery)
    }

    nonisolated private static func writeStatus(_ phase: String, available: Bool) {
        let report: [String: Any] = ["phase": phase, "available": available, "timestamp": Date().timeIntervalSince1970]
        if let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("fitness-summary-startup.json"), options: .atomic)
        }
    }

    nonisolated private static func consume(_ summaries: [HKActivitySummary]?, error: Error?, calendar: Calendar) {
        let now = Date()
        let rows: [FitnessDailyActivity] = (summaries ?? []).compactMap { summary in
            guard let date = calendar.date(from: summary.dateComponents(for: calendar)) else { return nil }
            return FitnessDailyActivity(day: date,
                activeEnergyKcal: summary.activeEnergyBurned.doubleValue(for: .kilocalorie()),
                exerciseMinutes: summary.appleExerciseTime.doubleValue(for: .minute()))
        }
        let result = error == nil ? FitnessActivityEvaluator.evaluate(rows, now: now, calendar: calendar) : nil
        FitnessValueStore.publish(result, now: now, calendar: calendar)
        // Availability only. Health measurements are not persisted in this diagnostic.
        let report: [String: Any] = ["schema": "fitness-summary-adapter-v1", "timestamp": now.timeIntervalSince1970,
            "visibleSummaryDays": rows.count, "baselineDays": result?.baselineDays ?? 0,
            "fitnessInputAvailable": result != nil, "writesToHealthKit": false,
            "errorDomain": (error as NSError?)?.domain ?? "", "errorCode": (error as NSError?)?.code ?? 0]
        if let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
           let data = try? JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]) {
            try? data.write(to: folder.appendingPathComponent("fitness-summary-adapter.json"), options: .atomic)
        }
    }
}

@_cdecl("fitness_summary_adapter_start")
public func fitnessSummaryAdapterStart() {
    Task { @MainActor in FitnessSummaryReader.shared.start() }
}
