import Foundation
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
let today = Date(timeIntervalSince1970: 1_794_960_000)
@MainActor func row(_ daysAgo: Int, _ kcal: Double = 400) -> FitnessDailyActivity {
    FitnessDailyActivity(day: calendar.date(byAdding: .day, value: -daysAgo, to: today)!, activeEnergyKcal: kcal, exerciseMinutes: 20)
}
let baseline = (2...6).map { row($0) }
var checked = 0
@MainActor func check(_ value: Bool, _ name: String) {
    precondition(value, name); checked += 1; print("PASS \(name)")
}
check(FitnessActivityEvaluator.evaluate(baseline + [row(1)], now: today, calendar: calendar)?.normalizedActivity == 0, "Observed yesterday and baseline produce neutral activity")
check(FitnessActivityEvaluator.evaluate(baseline, now: today, calendar: calendar) == nil, "Missing yesterday stays unavailable")
check(FitnessActivityEvaluator.evaluate(Array(baseline.prefix(4)) + [row(1)], now: today, calendar: calendar) == nil, "Four baseline days do not qualify")
check(FitnessActivityEvaluator.evaluate([row(1)] + Array(repeating: row(2), count: 8), now: today, calendar: calendar) == nil, "Duplicates cannot establish baseline")
check(FitnessActivityEvaluator.evaluate(baseline + [row(1), row(1, 800)], now: today, calendar: calendar) == nil, "Conflicting yesterday is rejected")
check(FitnessActivityEvaluator.evaluate(baseline + [row(1, .nan)], now: today, calendar: calendar) == nil, "NaN yesterday rejected")
check(FitnessActivityEvaluator.evaluate(baseline + [row(1, -1)], now: today, calendar: calendar) == nil, "Negative energy rejected")
check(FitnessActivityEvaluator.evaluate(baseline + [row(1, 0)], now: today, calendar: calendar)?.normalizedActivity == 1, "Observed zero activity is valid; absent data is not zero")
check(FitnessActivityEvaluator.evaluate(baseline + [row(1, 4_000)], now: today, calendar: calendar)?.normalizedActivity == -1, "Activity is bounded")
check(FitnessActivityEvaluator.evaluate(baseline + [row(1), row(0, 10_000), row(-1, 10_000)], now: today, calendar: calendar)?.normalizedActivity == 0, "Today and future excluded")
check(FitnessActivityEvaluator.evaluate((2...8).map { row($0, 0) } + [row(1)], now: today, calendar: calendar) == nil, "Insufficient baseline energy stays unavailable")
check(FitnessActivityEvaluator.evaluate((25...30).map { row($0) } + [row(1)], now: today, calendar: calendar) == nil, "Old baseline excluded")
print("\(checked) checks passed")
