import Foundation
import HealthKit

/// Public HealthKit inputs only. Construction, decoding and encoding do not query HealthKit.
public struct PublicReadinessInputs: Codable, Sendable {
    public let schemaVersion: String
    public let generatedAt: Date
    public let requestedWindow: DateInterval
    public let timeZoneIdentifier: String
    public let calendarIdentifier: String
    public let sourcePolicy: String
    public let nights: [PublicNightInputs]
    public let activityDays: [PublicActivityDayInputs]
    public let workouts: [PublicWorkoutInputs]
    public let queries: [PublicInputQueryAudit]
    public let limitations: [String]
}

public enum PublicInputAvailability: String, Codable, Sendable {
    case observed, partial, notObserved, sourceRejected, qualityRejected, queryFailed, unavailable
}

public struct PublicInputFailure: Codable, Sendable {
    public let operation: String
    public let domain: String
    public let code: Int
    public let message: String
}

public struct PublicInputSource: Codable, Sendable, Hashable {
    public let bundleIdentifier: String
    public let name: String
    public let productType: String?
    public let sourceVersion: String?
    public let wasUserEntered: Bool
}

public struct PublicSourceContribution: Codable, Sendable {
    public let source: PublicInputSource
    public let count: Int
}

/// Nil value means unavailable, never a substituted baseline or a presumed zero.
/// observedWindow is the envelope of contributing samples, not continuous sensor coverage.
public struct PublicInputSignal: Codable, Sendable {
    public let typeIdentifier: String
    public let value: Double?
    public let unit: String
    public let aggregation: String
    public let availability: PublicInputAvailability
    public let count: Int
    public let visibleCount: Int
    public let sourceRejectedCount: Int
    public let qualityRejectedCount: Int
    public let requestedWindows: [DateInterval]
    public let observedWindow: DateInterval?
    public let sources: [PublicSourceContribution]
    public let failures: [PublicInputFailure]
}

public struct PublicInputQueryAudit: Codable, Sendable {
    public let operation: String
    public let executed: Bool
    public let visibleCount: Int
    public let acceptedSourceCount: Int
    public let failure: PublicInputFailure?
}

public struct PublicNightInputs: Codable, Sendable {
    public let morningDate: Date
    public let sleepSegments: [DateInterval]
    public let sleepDuration: PublicInputSignal
    public let heartRate: PublicInputSignal
    public let respiratoryRate: PublicInputSignal
    /// Absolute sleeping wrist temperature, never Apple's relative baseline deviation.
    public let wristTemperature: PublicInputSignal
    /// HealthKit percent-unit representation: 0...1, e.g. 0.97 means 97%.
    public let oxygenSaturation: PublicInputSignal
}

public struct PublicActivityDayInputs: Codable, Sendable {
    public let day: Date
    public let activeEnergy: PublicInputSignal
    /// UUIDs of accepted recorded workouts; absence does not prove no exercise occurred.
    public let recordedWorkoutIDs: [UUID]
}

public struct PublicWorkoutInputs: Codable, Sendable {
    public let id: UUID
    public let activityTypeRawValue: UInt
    public let window: DateInterval
    public let source: PublicInputSource
    public let duration: PublicInputSignal
    public let activeEnergy: PublicInputSignal
    public let perceivedEffort: PublicInputSignal
    public let estimatedEffort: PublicInputSignal
}

/// The caller owns authorization. This reader never requests or writes authorization/data.
/// Only an explicit call to fetch() executes read-only queries.
@available(watchOS 11.0, iOS 18.0, *)
public final class PublicHealthKitInputsReader: Sendable {
    private let store: HKHealthStore
    private let calendar: Calendar
    private let timeout: TimeInterval

    public init(store: HKHealthStore, calendar: Calendar = .current, queryTimeout: TimeInterval = 12) {
        self.store = store
        self.calendar = calendar
        self.timeout = queryTimeout.isFinite ? min(60, max(1, queryTimeout)) : 12
    }

    public static var readTypes: Set<HKObjectType> {
        [HKCategoryType(.sleepAnalysis), HKQuantityType(.heartRate), HKQuantityType(.respiratoryRate),
         HKQuantityType(.appleSleepingWristTemperature), HKQuantityType(.oxygenSaturation),
         HKQuantityType(.activeEnergyBurned), HKObjectType.workoutType()]
    }

    /// Separate opt-in types: an integration must explicitly request authorization before enabling effort reads.
    public static var workoutEffortReadTypes: Set<HKObjectType> {
        [HKQuantityType(.workoutEffortScore), HKQuantityType(.estimatedWorkoutEffortScore)]
    }

    public static func authorizationReadTypes(includeWorkoutEffort: Bool = false) -> Set<HKObjectType> {
        includeWorkoutEffort ? readTypes.union(workoutEffortReadTypes) : readTypes
    }

    public func fetch(days: Int = 35, includeWorkoutEffort: Bool = false, endingAt end: Date = Date()) async throws -> PublicReadinessInputs {
        guard (1...90).contains(days), end.timeIntervalSinceReferenceDate.isFinite,
              let start = calendar.date(byAdding: .day, value: -days, to: calendar.startOfDay(for: end)), start < end else {
            throw NSError(domain: "PublicHealthKitInputs", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid history window"])
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "PublicHealthKitInputs", code: 2, userInfo: [NSLocalizedDescriptionKey: "HealthKit unavailable"])
        }
        let window = DateInterval(start: start, end: end)
        // Independent reads. Each result retains its own error so one failed type cannot erase other inputs.
        async let sleepRead = query(HKCategoryType(.sleepAnalysis), in: window)
        async let heartRead = query(HKQuantityType(.heartRate), in: window)
        async let respiratoryRead = query(HKQuantityType(.respiratoryRate), in: window)
        async let temperatureRead = query(HKQuantityType(.appleSleepingWristTemperature), in: window)
        async let oxygenRead = query(HKQuantityType(.oxygenSaturation), in: window)
        async let energyRead = query(HKQuantityType(.activeEnergyBurned), in: window)
        async let workoutRead = query(HKObjectType.workoutType(), in: window)
        async let effortRead = effortRelationships(in: window, enabled: includeWorkoutEffort)
        let (sleep, heart, respiratory, temperature, oxygen, energy, workoutResult, efforts) =
            await (sleepRead, heartRead, respiratoryRead, temperatureRead, oxygenRead, energyRead, workoutRead, effortRead)

        let asleep = Set([HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue,
                          HKCategoryValueSleepAnalysis.asleepCore.rawValue,
                          HKCategoryValueSleepAnalysis.asleepDeep.rawValue,
                          HKCategoryValueSleepAnalysis.asleepREM.rawValue])
        let sleepSamples = sleep.samples.compactMap { $0 as? HKCategorySample }
            .filter { trusted($0) && asleep.contains($0.value) && $0.startDate < $0.endDate }
        let intervals = sleepSamples.compactMap { sample -> DateInterval? in
            let lo = max(start, sample.startDate), hi = min(end, sample.endDate)
            return lo < hi ? DateInterval(start: lo, end: hi) : nil
        }
        let groups = NightQuality.nights(intervals, calendar: calendar)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let nights = groups.keys.sorted().compactMap { morning -> PublicNightInputs? in
            guard let segments = groups[morning], !segments.isEmpty else { return nil }
            let contributingSleep = sleepSamples.filter { overlaps($0, windows: segments) }
            let visibleSleep = sleep.samples.filter { overlaps($0, windows: segments) }
            let duration = signal(type: HKCategoryType(.sleepAnalysis).identifier,
                                  value: segments.reduce(0) { $0 + $1.duration } / 3600,
                                  unit: "h", method: "union-of-trusted-asleep-intervals; local-noon-to-noon",
                                  visible: visibleSleep, accepted: contributingSleep,
                                  rejectedQuality: 0, windows: segments, failure: sleep.failure)
            return PublicNightInputs(morningDate: morning, sleepSegments: segments, sleepDuration: duration,
                heartRate: aggregate(heart, type: .heartRate, unit: bpm, unitName: "count/min", windows: segments, accept: { $0 > 0 }),
                respiratoryRate: aggregate(respiratory, type: .respiratoryRate, unit: bpm, unitName: "count/min", windows: segments, accept: { $0 > 0 }),
                // This public type is already a whole-night aggregate; allow overlap with fragmented sleep stages.
                wristTemperature: aggregate(temperature, type: .appleSleepingWristTemperature, unit: .degreeCelsius(), unitName: "degC-absolute", windows: segments, requireContained: false, accept: { _ in true }),
                oxygenSaturation: aggregate(oxygen, type: .oxygenSaturation, unit: .percent(), unitName: "fraction", windows: segments, accept: { $0 > 0 && $0 <= 1 }))
        }

        let acceptedWorkouts = workoutResult.samples.compactMap { $0 as? HKWorkout }
            .filter { trusted($0) && $0.startDate < $0.endDate }
        var workouts: [PublicWorkoutInputs] = []
        var directEffortAudits: [PublicInputQueryAudit] = []
        for workout in acceptedWorkouts {
            let windows = [DateInterval(start: workout.startDate, end: workout.endDate)]
            // Link by public relationship UUID, never by coincident timestamps.
            let related = efforts.relationships.filter { $0.workout.uuid == workout.uuid }
                .flatMap { $0.samples ?? [] }
            var perceived = Samples(samples: unique(related.filter { ($0 as? HKQuantitySample)?.quantityType.identifier == HKQuantityType(.workoutEffortScore).identifier }), failure: efforts.failure)
            var estimated = Samples(samples: unique(related.filter { ($0 as? HKQuantitySample)?.quantityType.identifier == HKQuantityType(.estimatedWorkoutEffortScore).identifier }), failure: efforts.failure)
            if includeWorkoutEffort, perceived.samples.isEmpty, estimated.samples.isEmpty {
                async let directPerceived = query(HKQuantityType(.workoutEffortScore), matching: HKQuery.predicateForWorkoutEffortSamplesRelated(workout: workout, activity: nil))
                async let directEstimated = query(HKQuantityType(.estimatedWorkoutEffortScore), matching: HKQuery.predicateForWorkoutEffortSamplesRelated(workout: workout, activity: nil))
                (perceived, estimated) = await (directPerceived, directEstimated)
                for (label, result) in [("directPerceivedEffort", perceived), ("directEstimatedEffort", estimated)] {
                    directEffortAudits.append(PublicInputQueryAudit(operation: label, executed: true,
                        visibleCount: result.samples.count, acceptedSourceCount: result.samples.count, failure: result.failure))
                }
            }
            let durationValue = workout.duration.isFinite && workout.duration > 0 ? workout.duration : nil
            let duration = signal(type: "HKWorkout.duration", value: durationValue, unit: "s", method: "recorded-workout-duration",
                                  visible: [workout], accepted: durationValue == nil ? [] : [workout], rejectedQuality: durationValue == nil ? 1 : 0,
                                  windows: windows, failure: nil)
            let kcal = workout.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            let validKcal = kcal.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
            let workoutEnergy = signal(type: "HKWorkout.statistics.activeEnergyBurned", value: validKcal, unit: "kcal", method: "recorded-workout-statistic",
                                       visible: [workout], accepted: validKcal == nil ? [] : [workout], rejectedQuality: kcal != nil && validKcal == nil ? 1 : 0,
                                       windows: windows, failure: nil)
            workouts.append(PublicWorkoutInputs(id: workout.uuid, activityTypeRawValue: workout.workoutActivityType.rawValue,
                window: windows[0], source: source(workout), duration: duration, activeEnergy: workoutEnergy,
                // Perceived effort may legitimately be user-entered. Preserve its provenance instead of calling it sensor data.
                perceivedEffort: aggregate(perceived, type: .workoutEffortScore, unit: .appleEffortScore(), unitName: "appleEffortScore", windows: windows,
                                           requireContained: false, trustSource: false, selectByWindow: false, disabled: !includeWorkoutEffort, accept: { $0 >= 0 && $0 <= 10 }),
                estimatedEffort: aggregate(estimated, type: .estimatedWorkoutEffortScore, unit: .appleEffortScore(), unitName: "appleEffortScore", windows: windows,
                                           requireContained: false, trustSource: false, selectByWindow: false, disabled: !includeWorkoutEffort, accept: { $0 >= 0 && $0 <= 10 })))
        }
        var activityDays: [PublicActivityDayInputs] = []
        var cursor = start
        while cursor < end, let next = calendar.date(byAdding: .day, value: 1, to: cursor), next > cursor {
            let dayWindow = DateInterval(start: cursor, end: min(next, end))
            activityDays.append(PublicActivityDayInputs(day: cursor, activeEnergy: energyForDay(energy, window: dayWindow),
                recordedWorkoutIDs: workouts.filter { dayWindow.start <= $0.window.start && $0.window.start < dayWindow.end }.map(\.id)))
            cursor = next
        }
        let queryRows = [(HKCategoryType(.sleepAnalysis).identifier, sleep), (HKQuantityType(.heartRate).identifier, heart),
                         (HKQuantityType(.respiratoryRate).identifier, respiratory), (HKQuantityType(.appleSleepingWristTemperature).identifier, temperature),
                         (HKQuantityType(.oxygenSaturation).identifier, oxygen), (HKQuantityType(.activeEnergyBurned).identifier, energy),
                         (HKObjectType.workoutType().identifier, workoutResult)]
        var audits = queryRows.map { PublicInputQueryAudit(operation: $0.0, executed: true, visibleCount: $0.1.samples.count,
                                                         acceptedSourceCount: $0.1.samples.filter(trusted).count, failure: $0.1.failure) }
        audits.append(PublicInputQueryAudit(operation: "HKWorkoutEffortRelationshipQuery", executed: includeWorkoutEffort, visibleCount: efforts.relationships.count,
                                           acceptedSourceCount: efforts.relationships.filter { relation in acceptedWorkouts.contains { $0.uuid == relation.workout.uuid } }.count,
                                           failure: efforts.failure))
        return PublicReadinessInputs(schemaVersion: "public-healthkit-inputs-v1", generatedAt: Date(), requestedWindow: window,
            timeZoneIdentifier: calendar.timeZone.identifier, calendarIdentifier: String(describing: calendar.identifier),
            sourcePolicy: "NightQuality.trustedSource: Apple Watch + com.apple.health.* + non-manual. Effort: public relationship to an accepted workout; source/manual flag retained.",
            nights: nights, activityDays: activityDays, workouts: workouts, queries: audits + directEffortAudits,
            limitations: ["Empty read results cannot distinguish denied read access from absent samples.",
                          "No sleep score, Apple training load, Vitals classification, temperature delta or Apple baseline is inferred.",
                          "Night measurements are local medians of visible samples; envelope/count do not establish full-night coverage.",
                          "Sleeping wrist temperature is absolute and may span awake gaps; it is assigned by overlap with sleep.",
                          "Daily active energy is a conservative sum of complete, nonoverlapping samples from one trusted source; ambiguous/partial coverage is explicit.",
                          "Workouts are assigned to the day they start; recorded workouts are not a complete measure of physical activity."])
    }

    private func aggregate(_ result: Samples, type: HKQuantityTypeIdentifier, unit: HKUnit, unitName: String,
                           windows: [DateInterval], requireContained: Bool = true, trustSource: Bool = true,
                           selectByWindow: Bool = true, disabled: Bool = false, accept: (Double) -> Bool) -> PublicInputSignal {
        if disabled {
            return PublicInputSignal(typeIdentifier: HKQuantityType(type).identifier, value: nil, unit: unitName,
                aggregation: "disabled-by-caller; no-query-executed", availability: .unavailable,
                count: 0, visibleCount: 0, sourceRejectedCount: 0, qualityRejectedCount: 0,
                requestedWindows: windows, observedWindow: nil, sources: [], failures: [])
        }
        let visible = result.samples.filter { !selectByWindow || overlaps($0, windows: windows) }
        let accepted = visible.compactMap { sample -> (HKSample, Double)? in
            guard (!trustSource || trusted(sample)), let sample = sample as? HKQuantitySample,
                  (!requireContained || contained(sample, windows: windows)) else { return nil }
            let value = sample.quantity.doubleValue(for: unit)
            return value.isFinite && accept(value) ? (sample, value) : nil
        }
        let qualityRejected = visible.filter { !trustSource || trusted($0) }.count - accepted.count
        return signal(type: HKQuantityType(type).identifier, value: median(accepted.map(\.1)), unit: unitName,
                      method: "median-of-visible-samples", visible: visible, accepted: accepted.map(\.0),
                      rejectedQuality: qualityRejected, windows: windows, failure: result.failure, trustSource: trustSource)
    }

    private func energyForDay(_ result: Samples, window: DateInterval) -> PublicInputSignal {
        let visible = result.samples.filter { overlaps($0, windows: [window]) }
        let usable = visible.compactMap { sample -> (HKSample, Double)? in
            guard trusted(sample), contained(sample, windows: [window]), let quantity = sample as? HKQuantitySample else { return nil }
            let value = quantity.quantity.doubleValue(for: .kilocalorie())
            return value.isFinite && value >= 0 ? (sample, value) : nil
        }.sorted { $0.0.startDate < $1.0.startDate }
        let sources = Set(usable.map { source($0.0) })
        let overlap = zip(usable, usable.dropFirst()).contains { $0.0.endDate > $1.0.startDate }
        let ambiguous = sources.count > 1 || overlap
        let accepted = ambiguous ? [] : usable
        let values = accepted.map(\.1)
        let sum = values.reduce(0, +)
        let value = !values.isEmpty && sum.isFinite ? sum : nil
        let rejected = visible.filter(trusted).count - accepted.count
        let ambiguityFailure = ambiguous ? PublicInputFailure(operation: HKQuantityType(.activeEnergyBurned).identifier,
            domain: "PublicHealthKitInputs", code: 3, message: "Multiple trusted sources or overlapping energy samples; no total fabricated") : result.failure
        return signal(type: HKQuantityType(.activeEnergyBurned).identifier, value: value, unit: "kcal",
                      method: "sum-of-complete-nonoverlapping-samples-single-source", visible: visible, accepted: accepted.map(\.0),
                      rejectedQuality: rejected, windows: [window], failure: ambiguityFailure)
    }

    private func signal(type: String, value: Double?, unit: String, method: String, visible: [HKSample], accepted: [HKSample],
                        rejectedQuality: Int, windows: [DateInterval], failure: PublicInputFailure?, trustSource: Bool = true) -> PublicInputSignal {
        let sourceRejected = trustSource ? visible.filter { !trusted($0) }.count : 0
        let state: PublicInputAvailability
        if value != nil { state = failure != nil || rejectedQuality > 0 || sourceRejected > 0 ? .partial : .observed }
        else if failure != nil { state = .queryFailed }
        else if rejectedQuality > 0 { state = .qualityRejected }
        else if sourceRejected > 0 { state = .sourceRejected }
        else { state = .notObserved }
        let contribution = Dictionary(grouping: accepted, by: source).map { PublicSourceContribution(source: $0.key, count: $0.value.count) }
            .sorted { ($0.source.bundleIdentifier, $0.source.productType ?? "", $0.source.sourceVersion ?? "") < ($1.source.bundleIdentifier, $1.source.productType ?? "", $1.source.sourceVersion ?? "") }
        let observed: DateInterval?
        if let start = accepted.map(\.startDate).min(), let end = accepted.map(\.endDate).max(), start <= end { observed = DateInterval(start: start, end: end) }
        else { observed = nil }
        return PublicInputSignal(typeIdentifier: type, value: value, unit: unit, aggregation: method, availability: state,
                                 count: accepted.count, visibleCount: visible.count, sourceRejectedCount: sourceRejected,
                                 qualityRejectedCount: rejectedQuality, requestedWindows: windows, observedWindow: observed,
                                 sources: contribution, failures: failure.map { [$0] } ?? [])
    }

    private func source(_ sample: HKSample) -> PublicInputSource {
        PublicInputSource(bundleIdentifier: sample.sourceRevision.source.bundleIdentifier, name: sample.sourceRevision.source.name,
                          productType: sample.sourceRevision.productType, sourceVersion: sample.sourceRevision.version,
                          wasUserEntered: (sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool) == true)
    }
    private func trusted(_ sample: HKSample) -> Bool {
        let s = source(sample)
        return NightQuality.trustedSource(product: s.productType ?? "", bundle: s.bundleIdentifier, manual: s.wasUserEntered)
    }
    private func overlaps(_ sample: HKSample, windows: [DateInterval]) -> Bool {
        windows.contains { sample.startDate < $0.end && sample.endDate > $0.start || sample.startDate == sample.endDate && sample.startDate >= $0.start && sample.startDate < $0.end }
    }
    private func contained(_ sample: HKSample, windows: [DateInterval]) -> Bool {
        windows.contains { sample.startDate >= $0.start && sample.endDate <= $0.end && sample.startDate < $0.end }
    }
    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let a = values.sorted(), i = a.count / 2
        return a.count.isMultiple(of: 2) ? a[i - 1] / 2 + a[i] / 2 : a[i]
    }
    private func unique(_ samples: [HKSample]) -> [HKSample] {
        var seen = Set<UUID>()
        return samples.filter { seen.insert($0.uuid).inserted }
    }

    private struct Samples: Sendable { let samples: [HKSample]; let failure: PublicInputFailure? }
    private struct Efforts: Sendable { let relationships: [HKWorkoutEffortRelationship]; let failure: PublicInputFailure? }

    private func query(_ type: HKSampleType, in window: DateInterval) async -> Samples {
        await query(type, matching: HKQuery.predicateForSamples(withStart: window.start, end: window.end))
    }

    private func query(_ type: HKSampleType, matching predicate: NSPredicate) async -> Samples {
        await withCheckedContinuation { continuation in
            let once = PublicInputContinuation< Samples >(continuation)
            let query = HKSampleQuery(sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                    once.finish(Samples(samples: self.unique(samples ?? []), failure: error.map { self.failure($0, operation: type.identifier) }))
                }
            store.execute(query)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [store] in
                if once.finish(Samples(samples: [], failure: self.timeoutFailure(type.identifier))) { store.stop(query) }
            }
        }
    }

    private func effortRelationships(in window: DateInterval, enabled: Bool) async -> Efforts {
        guard enabled else { return Efforts(relationships: [], failure: nil) }
        return await withCheckedContinuation { continuation in
            let once = PublicInputContinuation<Efforts>(continuation)
            let query = HKWorkoutEffortRelationshipQuery(
                predicate: HKQuery.predicateForSamples(withStart: window.start, end: window.end), anchor: nil, options: .default) { query, relationships, _, error in
                    if once.finish(Efforts(relationships: relationships ?? [], failure: error.map { self.failure($0, operation: "HKWorkoutEffortRelationshipQuery") })) {
                        self.store.stop(query) // One snapshot; this public query otherwise remains long-running.
                    }
                }
            store.execute(query)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [store] in
                if once.finish(Efforts(relationships: [], failure: self.timeoutFailure("HKWorkoutEffortRelationshipQuery"))) { store.stop(query) }
            }
        }
    }

    private func failure(_ error: Error, operation: String) -> PublicInputFailure {
        let ns = error as NSError
        return PublicInputFailure(operation: operation, domain: ns.domain, code: ns.code, message: ns.localizedDescription)
    }
    private func timeoutFailure(_ operation: String) -> PublicInputFailure {
        PublicInputFailure(operation: operation, domain: "PublicHealthKitInputs", code: 4, message: "Public read query timed out")
    }
}

private final class PublicInputContinuation<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Never>?
    init(_ continuation: CheckedContinuation<Value, Never>) { self.continuation = continuation }
    @discardableResult func finish(_ value: Value) -> Bool {
        lock.lock()
        let current = continuation
        continuation = nil
        lock.unlock()
        guard let current else { return false }
        current.resume(returning: value)
        return true
    }
}
