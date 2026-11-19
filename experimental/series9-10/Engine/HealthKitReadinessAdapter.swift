import Foundation
import HealthKit

/// Acumulador seguro de intervalos RR que aplica filtrado de artefactos y gaps
/// Adaptador público para consultar HealthKit, agrupar por noche y normalizar unidades
public final class HealthKitReadinessAdapter: Sendable {

    public let healthStore: HKHealthStore
    public let calendar: Calendar

    public init(healthStore: HKHealthStore = HKHealthStore(), calendar: Calendar = .current) {
        self.healthStore = healthStore
        self.calendar = calendar
    }

    public static var readTypes: Set<HKObjectType> { [
            HKSeriesType.heartbeat(),
            HKCategoryType(.sleepAnalysis),
            HKQuantityType(.heartRate),
            HKQuantityType(.restingHeartRate),
            HKQuantityType(.heartRateVariabilitySDNN),
            HKQuantityType(.appleSleepingWristTemperature),
            HKQuantityType(.respiratoryRate),
            HKQuantityType(.oxygenSaturation),
            HKObjectType.activitySummaryType()
        ]
    }

    /// Solicita autorización para todas las métricas públicas necesarias (SOLO LECTURA)
    public func requestAuthorization() async throws {
        guard HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "HealthKitReadinessAdapter", code: 1, userInfo: [NSLocalizedDescriptionKey: "HealthKit no está disponible en este dispositivo"])
        }

        try await healthStore.requestAuthorization(toShare: [], read: Self.readTypes)
    }

    /// Consulta los últimos N días y produce un array de resúmenes nocturnos
    private let storage = ReadinessStorageCoordinator()

    // Only non-manual Apple Watch samples from Apple's health source qualify.
    private func trusted(_ sample: HKSample) -> Bool {
        let product = sample.sourceRevision.productType ?? ""
        return NightQuality.trustedSource(product: product, bundle: sample.sourceRevision.source.bundleIdentifier, manual: (sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool) == true)
    }

    public func fetchOvernightHistory(days: Int = 35) async throws -> [OvernightSummary] {
        let now = Date()
        let deadline = now.addingTimeInterval(20)
        let start = calendar.date(byAdding: .day, value: -days, to: now)!
        let allSleep = try await queryCategorySamples(type: HKCategoryType(.sleepAnalysis), startDate: start, endDate: now)
        let sleep = allSleep.filter { trusted($0) }
        let asleepValues = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        let intervals = sleep.filter { asleepValues.contains($0.value) && $0.endDate > $0.startDate }.map { DateInterval(start: $0.startDate, end: $0.endDate) }
        let nights = NightQuality.nights(intervals, calendar: calendar)
        let allSeries = try await queryHeartbeatSamples(startDate: start, endDate: now)
        let series = allSeries.filter { trusted($0) }
        let resting = try await queryRaw(type: HKQuantityType(.restingHeartRate), startDate: start, endDate: now).compactMap { $0 as? HKQuantitySample }.filter { trusted($0) }
        await storage.pruneOldEntries()
        var summaries: [OvernightSummary] = []
        var cacheHits = 0
        var enumerated = 0
        var matched = 0
        for (morning, segments) in nights.sorted(by: { $0.key < $1.key }) {
            let hours = segments.reduce(0) { $0 + $1.duration } / 3600
            // Conservative engineering gates; not a validated clinical quality measure.
            guard hours >= 3, hours <= 14, let end = segments.last?.end, now.timeIntervalSince(end) >= 1800 else { continue }
            var values: [Double] = []
            for sample in series where NightQuality.contains(start: sample.startDate, end: sample.endDate, segments: segments) {
                matched += 1
                guard Date() < deadline else { throw ReadinessFailure.message("Preparando caché; vuelve a actualizar para continuar sin reprocesar series válidas.") }
                if let cached = await storage.getCachedRMSSD(for: sample.uuid) { cacheHits += 1; values.append(cached) }
                else {
                    enumerated += 1
                    if let computed = await computeRMSSD(for: sample), computed.rmssd > 0 {
                    await storage.store(entry: HeartbeatCacheEntry(sampleUUID: sample.uuid, endDate: sample.endDate, rmssdMs: computed.rmssd, validDifferencesCount: computed.count))
                    values.append(computed.rmssd)
                    }
                }
            }
            let rhr = resting.filter { calendar.isDate($0.endDate, inSameDayAs: morning) }.map { $0.quantity.doubleValue(for: .count().unitDivided(by: .minute())) }.filter { $0.isFinite && $0 > 0 }
            summaries.append(OvernightSummary(morningDate: morning, rmssdMs: values.isEmpty ? nil : RobustReadinessEngine.median(values), restingHRBpm: rhr.isEmpty ? nil : RobustReadinessEngine.median(rhr), sleepDurationHours: hours))
        }
        let audit = HealthReadAudit(calculatedAt: Date(), elapsedSeconds: Date().timeIntervalSince(now), visibleSleepSamples: allSleep.count, trustedSleepSamples: sleep.count, visibleHeartbeatSeries: allSeries.count, trustedHeartbeatSeries: series.count, seriesInsideSleep: matched, cacheHits: cacheHits, enumeratedSeries: enumerated, acceptedNights: summaries.count, nightsWithRMSSD: summaries.filter { $0.rmssdMs != nil }.count, todayHasRMSSD: summaries.contains { calendar.isDate($0.morningDate, inSameDayAs: now) && $0.rmssdMs != nil }, visibleSources: Array(Set((allSleep as [HKSample] + allSeries).map { "\($0.sourceRevision.productType ?? "unknown") | \($0.sourceRevision.source.bundleIdentifier)" })).sorted())
        if let data = try? JSONEncoder().encode(audit) { await storage.saveAudit(data) }
        return summaries
    }

    // MARK: - Procesamiento de Series de Latidos

    public func computeRMSSD(for sample: HKHeartbeatSeriesSample) async -> (rmssd: Double, count: Int)? {
        await withCheckedContinuation { continuation in
            let state = RRQueryState()

            let query = HKHeartbeatSeriesQuery(heartbeatSeries: sample) { _, time, gap, done, error in
                state.lock.lock()
                defer { state.lock.unlock() }
                guard !state.finished else { return }

                if error != nil {
                    state.finished = true
                    continuation.resume(returning: nil)
                    return
                }

                state.accumulator.append(time: time, precededByGap: gap)

                if done {
                    state.finished = true
                    continuation.resume(returning: state.accumulator.rmssdMilliseconds.map { ($0, state.accumulator.validDifferencesCount) })
                }
            }

            healthStore.execute(query)

            // Timeout de seguridad de 8 segundos
            DispatchQueue.global().asyncAfter(deadline: .now() + 8.0) { [weak self] in
                state.lock.lock()
                defer { state.lock.unlock() }
                guard !state.finished else { return }
                state.finished = true
                self?.healthStore.stop(query)
                continuation.resume(returning: nil)
            }
        }
    }

    // MARK: - Consultas Auxiliares Públicas

    private func queryRaw(type: HKSampleType, startDate: Date, endDate: Date) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let completion = QueryCompletion<[HKSample]>(continuation)
            let query = HKSampleQuery(sampleType: type, predicate: HKQuery.predicateForSamples(withStart: startDate, end: endDate), limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { completion.finish(.failure(error)) }
                else { completion.finish(.success(samples ?? [])) }
            }
            healthStore.execute(query)
            DispatchQueue.global().asyncAfter(deadline: .now() + 12) { [healthStore] in
                if completion.finish(.failure(ReadinessFailure.message("Salud tardó demasiado; vuelve a actualizar."))) { healthStore.stop(query) }
            }
        }
    }
    private func queryCategorySamples(type: HKCategoryType, startDate: Date, endDate: Date) async throws -> [HKCategorySample] {
        try await queryRaw(type: type, startDate: startDate, endDate: endDate).compactMap { $0 as? HKCategorySample }
    }
    private func queryHeartbeatSamples(startDate: Date, endDate: Date) async throws -> [HKHeartbeatSeriesSample] {
        try await queryRaw(type: HKSeriesType.heartbeat(), startDate: startDate, endDate: endDate).compactMap { $0 as? HKHeartbeatSeriesSample }
    }
}
private final class RRQueryState: @unchecked Sendable {
    let lock = NSLock()
    var accumulator = SafeRRAccumulator()
    var finished = false
}
