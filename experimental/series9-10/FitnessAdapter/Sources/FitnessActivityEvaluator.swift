import Foundation

struct FitnessDailyActivity: Codable, Sendable, Equatable {
    let day: Date
    let activeEnergyKcal: Double
    let exerciseMinutes: Double
}

struct FitnessActivityResult: Codable, Sendable {
    let yesterday: Date
    let yesterdayEnergyKcal: Double
    let yesterdayExerciseMinutes: Double
    let baselineDays: Int
    let baselineMedianKcal: Double
    /// Same signed activity mapping observed in the recovered build 38.
    let normalizedActivity: Double
}

enum FitnessActivityEvaluator {
    static func evaluate(_ rows: [FitnessDailyActivity], now: Date, calendar: Calendar) -> FitnessActivityResult? {
        let today = calendar.startOfDay(for: now)
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: today),
              let earliest = calendar.date(byAdding: .day, value: -21, to: yesterday) else { return nil }
        var byDay: [Date: FitnessDailyActivity] = [:]
        var conflictingDays = Set<Date>()
        for row in rows {
            let day = calendar.startOfDay(for: row.day)
            guard day >= earliest, day < today, row.activeEnergyKcal.isFinite, row.activeEnergyKcal >= 0,
                  row.exerciseMinutes.isFinite, (0...1440).contains(row.exerciseMinutes) else { continue }
            let normalized = FitnessDailyActivity(day: day, activeEnergyKcal: row.activeEnergyKcal, exerciseMinutes: row.exerciseMinutes)
            if let prior = byDay[day], prior != normalized { conflictingDays.insert(day) }
            else { byDay[day] = normalized }
        }
        for day in conflictingDays { byDay.removeValue(forKey: day) }
        guard let recent = byDay[yesterday] else { return nil }
        let baseline = byDay.values.filter { $0.day < yesterday }.map(\.activeEnergyKcal).sorted()
        guard baseline.count >= 5 else { return nil }
        let middle = baseline.count / 2
        let median = baseline.count.isMultiple(of: 2) ? (baseline[middle - 1] / 2 + baseline[middle] / 2) : baseline[middle]
        guard median.isFinite, median >= 50 else { return nil }
        let activity = max(-1, min(1, (1 - recent.activeEnergyKcal / median) / 0.75))
        guard activity.isFinite else { return nil }
        return FitnessActivityResult(yesterday: yesterday, yesterdayEnergyKcal: recent.activeEnergyKcal,
            yesterdayExerciseMinutes: recent.exerciseMinutes, baselineDays: baseline.count,
            baselineMedianKcal: median, normalizedActivity: activity)
    }
}
