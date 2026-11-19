import SwiftUI
@main struct ExperimentalHarnessApp: App {
 @State private var status = "Running synthetic checks…"
 var body: some Scene {
  WindowGroup {
   ScrollView { VStack(alignment: .leading, spacing: 10) {
    Text("Experimental checks").font(.headline)
    Text(status).accessibilityIdentifier("test-result")
    Text("Synthetic data only. This harness tests our engine; it is not the Cobalt app or a physical-watch compatibility result.").font(.footnote)
   }.padding() }
   .task {
    do {
     let engine = try await RegressionChecks.run()
     let fitness = FitnessChecks.run()
     let models = ModelChecks.run()
     status = "PASS: \(engine + fitness + models) checks\nEngine: \(engine)\nFitness: \(fitness)\nModel sources: \(models)"
     print(status)
    } catch { status = "FAIL: \(error.localizedDescription)" }
   }
  }
 }
}

import Foundation


/// Estado de disponibilidad del cálculo de Readiness
public enum ReadinessState: Equatable, Sendable {
    case ready(score: Int, confidence: Double)
    case calibrating(daysAvailable: Int, daysRequired: Int)
    case insufficientData(missingSignals: [String])
    case error(description: String)
}

/// Contenedor de una medición agregada para una noche específica
public struct OvernightSummary: Sendable, Equatable {
    public let morningDate: Date
    public let rmssdMs: Double?         // Calculado en milisegundos desde latidos reales
    public let restingHRBpm: Double?    // Frecuencia cardíaca en reposo
    public let sleepDurationHours: Double? // Horas totales en sueño
    public let wristTempDeltaC: Double? // Desviación de temperatura de muñeca en °C
    public let respiratoryRateBpm: Double? // Frecuencia respiratoria
    public let oxygenSaturation: Double?   // Saturación de oxígeno (0.0 a 1.0)

    public init(
        morningDate: Date,
        rmssdMs: Double? = nil,
        restingHRBpm: Double? = nil,
        sleepDurationHours: Double? = nil,
        wristTempDeltaC: Double? = nil,
        respiratoryRateBpm: Double? = nil,
        oxygenSaturation: Double? = nil
    ) {
        self.morningDate = morningDate
        self.rmssdMs = rmssdMs
        self.restingHRBpm = restingHRBpm
        self.sleepDurationHours = sleepDurationHours
        self.wristTempDeltaC = wristTempDeltaC
        self.respiratoryRateBpm = respiratoryRateBpm
        self.oxygenSaturation = oxygenSaturation
    }
}

/// Subpuntuación detallada de un factor fisiológico individual
public struct FactorEvaluation: Sendable, Equatable {
    public let name: String
    public let observedValue: Double
    public let baselineValue: Double
    public let deviationZ: Double      // Desviación tipificada acotada [-2.0, 2.0]
    public let componentScore: Double   // Escala 0 a 100
    public let baselineDays: Int
    public let weight: Double           // Peso en el cálculo final
}

/// Resultado completo y transparente del cálculo
public struct RobustReadinessResult: Sendable, Equatable {
    public let state: ReadinessState
    public let finalScore: Int?
    public let factors: [FactorEvaluation]
    public let baselineDaysUsed: Int
    public let calculatedAt: Date
    public let formulaVersion: String
}

/// Motor de cálculo de Readiness Fisiológico Robusto
/// Emplea Median Absolute Deviation (MAD), escala logarítmica para VFC (lnRMSSD) y manejo estricto de calidad.
public enum RobustReadinessEngine {

    public static let formulaVersion = "v3-experimental-nocturnal-mad"
    public static let minimumRequiredDays = 3
    public static let recommendedBaselineDays = 7

    public static func evaluate(
        history: [OvernightSummary],
        today: OvernightSummary,
        referenceDate: Date = Date()
    ) -> RobustReadinessResult {

        // 1. Filtrar noches históricas válidas que tengan VFC real
        let validHistory = history.filter { night in
            guard night.morningDate < today.morningDate, referenceDate.timeIntervalSince(night.morningDate) < 35 * 86400 else { return false }
            guard let rmssd = night.rmssdMs else { return false }
            return rmssd.isFinite && rmssd > 0 && (night.sleepDurationHours.map { $0.isFinite && $0 >= 3 && $0 <= 14 } ?? false)
        }.sorted { $0.morningDate < $1.morningDate }
        let uniqueDays = Set(validHistory.map { Calendar.current.startOfDay(for: $0.morningDate) })
        guard uniqueDays.count == validHistory.count else {
            return RobustReadinessResult(state: .error(description: "Historial con noches duplicadas"), finalScore: nil, factors: [], baselineDaysUsed: uniqueDays.count, calculatedAt: referenceDate, formulaVersion: formulaVersion)
        }

        // 2. Validación de disponibilidad para el día actual
        var missingToday: [String] = []
        guard Calendar.current.isDate(today.morningDate, inSameDayAs: referenceDate),
              let todayRMSSD = today.rmssdMs, todayRMSSD.isFinite, todayRMSSD > 0,
              let sleep = today.sleepDurationHours, sleep.isFinite, sleep >= 3, sleep <= 14 else {
            missingToday.append("VFC (RMSSD nocturno)")
            return RobustReadinessResult(
                state: .insufficientData(missingSignals: missingToday),
                finalScore: nil,
                factors: [],
                baselineDaysUsed: validHistory.count,
                calculatedAt: referenceDate,
                formulaVersion: formulaVersion
            )
        }

        // 3. Comprobación de calibración mínima (requiere al menos 3 días previos de línea base)
        if validHistory.count < minimumRequiredDays {
            return RobustReadinessResult(
                state: .calibrating(daysAvailable: validHistory.count, daysRequired: minimumRequiredDays),
                finalScore: nil,
                factors: [],
                baselineDaysUsed: validHistory.count,
                calculatedAt: referenceDate,
                formulaVersion: formulaVersion
            )
        }

        // 4. Evaluación de Factores
        var factors: [FactorEvaluation] = []

        // Factor A: VFC usando ln(RMSSD) - Mayor es favorable
        let historicalLnRMSSD = validHistory.map { log($0.rmssdMs!) }
        let todayLnRMSSD = log(todayRMSSD)
        let (hrvBase, hrvScale) = robustBaseline(values: historicalLnRMSSD, minimumScale: 0.05)
        let hrvZ = clamp((todayLnRMSSD - hrvBase) / hrvScale, min: -2.0, max: 2.0)
        let hrvScore = clamp(70.0 + (hrvZ * 15.0), min: 0.0, max: 100.0)
        factors.append(FactorEvaluation(
            name: "VFC (RMSSD)",
            observedValue: todayRMSSD,
            baselineValue: exp(hrvBase),
            deviationZ: hrvZ,
            componentScore: hrvScore,
            baselineDays: validHistory.count,
            weight: 0.45
        ))

        // Factor B: Pulso en Reposo (BPM) - Menor es favorable
        if let todayRHR = today.restingHRBpm, todayRHR.isFinite, todayRHR > 0 {
            let histRHR = validHistory.compactMap(\.restingHRBpm).filter { $0.isFinite && $0 > 0 }
            if histRHR.count >= minimumRequiredDays {
                let (rhrBase, rhrScale) = robustBaseline(values: histRHR, minimumScale: 2.0)
                // Invertido: menor pulso que la base produce Z positivo
                let rhrZ = clamp((rhrBase - todayRHR) / rhrScale, min: -2.0, max: 2.0)
                let rhrScore = clamp(70.0 + (rhrZ * 15.0), min: 0.0, max: 100.0)
                factors.append(FactorEvaluation(
                    name: "Pulso en Reposo",
                    observedValue: todayRHR,
                    baselineValue: rhrBase,
                    deviationZ: rhrZ,
                    componentScore: rhrScore,
                    baselineDays: histRHR.count,
                    weight: 0.25
                ))
            }
        }

        // Factor C: Sueño (Horas) - Comparado con objetivo saludable de 7.5h y baseline personal
        if let todaySleep = today.sleepDurationHours, todaySleep.isFinite, todaySleep > 0 {
            let histSleep = validHistory.compactMap(\.sleepDurationHours).filter { $0.isFinite && $0 > 0 }
            let sleepBase = histSleep.count >= minimumRequiredDays ? median(histSleep) : 7.5
            let sleepScore: Double
            if todaySleep >= 7.0 && todaySleep <= 9.0 {
                sleepScore = 85.0 + min(15.0, (todaySleep - 7.0) * 7.5)
            } else if todaySleep < 7.0 {
                sleepScore = max(30.0, 85.0 - ((7.0 - todaySleep) * 20.0))
            } else {
                sleepScore = 80.0
            }
            let sleepZ = clamp((todaySleep - sleepBase) / max(0.5, sleepBase * 0.1), min: -2.0, max: 2.0)
            factors.append(FactorEvaluation(
                name: "Sueño",
                observedValue: todaySleep,
                baselineValue: sleepBase,
                deviationZ: sleepZ,
                componentScore: sleepScore,
                baselineDays: histSleep.count,
                weight: 0.30
            ))
        }

        // 5. Normalización de pesos y suma ponderada estricta
        let totalWeight = factors.reduce(0.0) { $0 + $1.weight }
        guard totalWeight > 0 else {
            return RobustReadinessResult(
                state: .error(description: "No fue posible normalizar ponderaciones fisiológicas"),
                finalScore: nil,
                factors: [],
                baselineDaysUsed: validHistory.count,
                calculatedAt: referenceDate,
                formulaVersion: formulaVersion
            )
        }

        let weightedSum = factors.reduce(0.0) { $0 + ($1.componentScore * $1.weight) }
        let rawFinalScore = weightedSum / totalWeight
        let finalIntScore = Int(clamp(rawFinalScore, min: 0.0, max: 100.0).rounded())

        // Nivel de confianza según días de calibración disponibles (7+ días = 1.0)
        let confidence = min(1.0, Double(validHistory.count) / Double(recommendedBaselineDays))

        return RobustReadinessResult(
            state: .ready(score: finalIntScore, confidence: confidence),
            finalScore: finalIntScore,
            factors: factors,
            baselineDaysUsed: validHistory.count,
            calculatedAt: referenceDate,
            formulaVersion: formulaVersion
        )
    }

    // MARK: - Estadística Robusta

    public static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let count = sorted.count
        return count.isMultiple(of: 2)
            ? (sorted[count / 2 - 1] + sorted[count / 2]) / 2.0
            : sorted[count / 2]
    }

    public static func robustBaseline(values: [Double], minimumScale: Double) -> (base: Double, scale: Double) {
        let base = median(values)
        let absoluteDeviations = values.map { abs($0 - base) }
        let mad = median(absoluteDeviations) * 1.4826 // Equivalente a desviación estándar para distribución normal
        let scale = max(mad, minimumScale)
        return (base, scale)
    }

    private static func clamp(_ val: Double, min minVal: Double, max maxVal: Double) -> Double {
        return Swift.min(maxVal, Swift.max(minVal, val))
    }
}

import Foundation

public enum NightQuality {
    public static func trustedSource(product: String, bundle: String, manual: Bool) -> Bool {
        product.lowercased().hasPrefix("watch") && bundle.hasPrefix("com.apple.health.") && !manual
    }
    // Local noon-to-noon window. Split at the boundary rather than assigning stages independently.
    public static func nights(_ intervals: [DateInterval], calendar: Calendar) -> [Date: [DateInterval]] {
        var groups: [Date: [DateInterval]] = [:]
        for interval in intervals where interval.duration > 0 {
            var cursor = interval.start
            while cursor < interval.end {
                let day = calendar.startOfDay(for: cursor)
                let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day)!
                let morning = cursor < noon ? day : calendar.date(byAdding: .day, value: 1, to: day)!
                let boundary = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: morning)!
                let end = min(boundary, interval.end)
                groups[morning, default: []].append(DateInterval(start: cursor, end: end))
                cursor = end
            }
        }
        return groups.mapValues { segments in
            var merged: [DateInterval] = []
            for segment in segments.sorted(by: { $0.start < $1.start }) {
                if let last = merged.last, segment.start <= last.end {
                    merged[merged.count - 1] = DateInterval(start: last.start, end: max(last.end, segment.end))
                } else { merged.append(segment) }
            }
            return merged
        }
    }
    public static func contains(start: Date, end: Date, segments: [DateInterval]) -> Bool {
        end > start && segments.contains { start >= $0.start && end <= $0.end }
    }
}

import Foundation
public struct SafeRRAccumulator: Sendable {
    private var previousBeatTime: Double?
    private var previousInterval: Double?
    private var squaredDifferencesSum = 0.0
    private var validSeconds = 0.0

    public private(set) var validDifferencesCount = 0
    public private(set) var gapCount = 0
    public private(set) var rejectedIntervalsCount = 0

    public init() {}

    /// Procesa una marca de tiempo de latido
    /// - Parameters:
    ///   - time: Segundos transcurridos desde el inicio de la serie
    ///   - precededByGap: Indica si el reloj detectó una interrupción física o de contacto
    public mutating func append(time: Double, precededByGap: Bool) {
        guard time.isFinite && !time.isNaN else {
            previousBeatTime = nil
            previousInterval = nil
            rejectedIntervalsCount += 1
            return
        }

        if precededByGap {
            previousBeatTime = time
            previousInterval = nil
            gapCount += 1
            return
        }

        defer { previousBeatTime = time }
        guard let priorBeat = previousBeatTime else { return }

        let interval = time - priorBeat

        // Filtro fisiológico de plausibilidad (rango 0.285s a 2.0s <=> 30 a 210 BPM)
        guard interval >= 0.285 && interval <= 2.0 else {
            previousInterval = nil
            rejectedIntervalsCount += 1
            return
        }

        if let priorInterval = previousInterval {
            let diff = interval - priorInterval
            // Filtro de ectopia relativa (el salto entre latidos consecutivos no debe exceder 250ms)
            if abs(diff) <= 0.250 {
                squaredDifferencesSum += (diff * diff)
                validSeconds += interval
                validDifferencesCount += 1
            } else {
                rejectedIntervalsCount += 1
            }
        }
        previousInterval = interval
    }

    /// Devuelve el valor RMSSD calculado en milisegundos
    public var rmssdMilliseconds: Double? {
        guard validDifferencesCount >= 30, validSeconds >= 30, Double(rejectedIntervalsCount) / Double(validDifferencesCount + rejectedIntervalsCount) <= 0.2 else { return nil } // Requiere al menos 10 pares válidos para significancia estadística
        let meanSquareSeconds = squaredDifferencesSum / Double(validDifferencesCount)
        let rmssdSeconds = sqrt(meanSquareSeconds)
        let rmssdMs = rmssdSeconds * 1000.0
        return rmssdMs.isFinite ? rmssdMs : nil
    }
}

import Foundation

/// Entrada en caché del RMSSD para una serie de latidos procesada
public struct HeartbeatCacheEntry: Codable, Sendable {
    public let sampleUUID: UUID
    public let endDate: Date
    public let rmssdMs: Double
    public let validDifferencesCount: Int
    public let processedAt: Date

    public init(sampleUUID: UUID, endDate: Date, rmssdMs: Double, validDifferencesCount: Int, processedAt: Date = Date()) {
        self.sampleUUID = sampleUUID
        self.endDate = endDate
        self.rmssdMs = rmssdMs
        self.validDifferencesCount = validDifferencesCount
        self.processedAt = processedAt
    }
}

/// Registro persistente del último resultado de Readiness
public struct CachedReadinessSnapshot: Codable, Sendable {
    public let score: Int
    public let confidence: Double
    public let formulaVersion: String
    public let calculatedAt: Date
    public let baselineDaysUsed: Int

    public init(score: Int, confidence: Double, formulaVersion: String, calculatedAt: Date, baselineDaysUsed: Int) {
        self.score = score
        self.confidence = confidence
        self.formulaVersion = formulaVersion
        self.calculatedAt = calculatedAt
        self.baselineDaysUsed = baselineDaysUsed
    }
}

/// Gestor de almacenamiento en disco seguro y ligero para evitar re-procesar HKHeartbeatSeriesQuery
public actor ReadinessStorageCoordinator {

    private let fileManager = FileManager.default
    private let cacheDirectoryURL: URL
    private let seriesCacheFileURL: URL
    private let snapshotFileURL: URL

    // Caché en memoria sincronizada
    private var memoryCache: [UUID: HeartbeatCacheEntry] = [:]
    private var isLoaded = false

    public init(customDirectory: URL? = nil) {
        if let customDir = customDirectory {
            self.cacheDirectoryURL = customDir
        } else {
            let baseDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
            self.cacheDirectoryURL = baseDir.appendingPathComponent("ReadinessData", isDirectory: true)
        }
        self.seriesCacheFileURL = self.cacheDirectoryURL.appendingPathComponent("heartbeat_series_cache_v4.json")
        self.snapshotFileURL = self.cacheDirectoryURL.appendingPathComponent("latest_readiness_snapshot.json")
    }

    /// Carga la caché desde el almacenamiento local
    public func loadCacheIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true

        do {
            if !fileManager.fileExists(atPath: cacheDirectoryURL.path) {
                try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true)
            }

            if fileManager.fileExists(atPath: seriesCacheFileURL.path) {
                let data = try Data(contentsOf: seriesCacheFileURL)
                let entries = try JSONDecoder().decode([HeartbeatCacheEntry].self, from: data)
                self.memoryCache = Dictionary(entries.filter { $0.rmssdMs.isFinite && $0.rmssdMs > 0 && $0.validDifferencesCount >= 30 }.map { ($0.sampleUUID, $0) }, uniquingKeysWith: { _, new in new })
            }
        } catch {
            // Si el archivo está corrupto o es incompatible, reiniciar sin bloquear el cálculo
            self.memoryCache = [:]
        }
    }

    /// Consulta si una serie de latidos ya ha sido calculada previamente
    public func getCachedRMSSD(for sampleUUID: UUID) -> Double? {
        loadCacheIfNeeded()
        return memoryCache[sampleUUID]?.rmssdMs
    }

    /// Guarda el resultado de una nueva serie calculada
    public func store(entry: HeartbeatCacheEntry) {
        loadCacheIfNeeded()
        guard entry.rmssdMs.isFinite && entry.rmssdMs > 0 && entry.validDifferencesCount >= 30 else { return }
        memoryCache[entry.sampleUUID] = entry
        persistCache()
    }

    /// Guarda múltiples entradas por lote (batch insert)
    public func clearSnapshot() { try? fileManager.removeItem(at: snapshotFileURL) }

    public func storeBatch(entries: [HeartbeatCacheEntry]) {
        loadCacheIfNeeded()
        for e in entries where e.rmssdMs.isFinite && e.rmssdMs > 0 && e.validDifferencesCount >= 30 {
            memoryCache[e.sampleUUID] = e
        }
        persistCache()
    }

    /// Purga entradas con más de N días de antigüedad para mantener el almacenamiento mínimo
    public func pruneOldEntries(maxAgeDays: Int = 35) {
        loadCacheIfNeeded()
        let cutoff = Date().addingTimeInterval(-Double(maxAgeDays * 86400))
        let initialCount = memoryCache.count
        memoryCache = memoryCache.filter { $0.value.endDate >= cutoff }
        if memoryCache.count != initialCount {
            persistCache()
        }
    }

    /// Guarda la última puntuación calculada
    public func saveSnapshot(_ snapshot: CachedReadinessSnapshot) {
        loadCacheIfNeeded()
        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: snapshotFileURL, options: .atomic)
        } catch {}
    }

    /// Recupera la última puntuación calculada (útil para arranque instantáneo de la UI)
    public func loadSnapshot() -> CachedReadinessSnapshot? {
        loadCacheIfNeeded()
        guard fileManager.fileExists(atPath: snapshotFileURL.path) else { return nil }
        do {
            let data = try Data(contentsOf: snapshotFileURL)
            return try JSONDecoder().decode(CachedReadinessSnapshot.self, from: data)
        } catch {
            return nil
        }
    }

    public func saveAudit(_ data: Data) {
        loadCacheIfNeeded()
        try? data.write(to: cacheDirectoryURL.appendingPathComponent("health-read-audit.json"), options: .atomic)
    }

    private func persistCache() {
        do {
            let entries = Array(memoryCache.values)
            let data = try JSONEncoder().encode(entries)
            try data.write(to: seriesCacheFileURL, options: .atomic)
        } catch {}
    }
}

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

import Foundation
@MainActor enum FitnessChecks { static func run() -> Int {

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(secondsFromGMT: 0)!
let today = Date(timeIntervalSince1970: 1_794_960_000)
func row(_ daysAgo: Int, _ kcal: Double = 400) -> FitnessDailyActivity {
    FitnessDailyActivity(day: calendar.date(byAdding: .day, value: -daysAgo, to: today)!, activeEnergyKcal: kcal, exerciseMinutes: 20)
}
let baseline = (2...6).map { row($0) }
var checked = 0
func check(_ value: Bool, _ name: String) {
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

return checked
} }

import Foundation
@MainActor enum ModelChecks {
 static func run() -> Int {
  let identifiers = ["Watch7,1", "Watch7,10", "Watch7,11", "Watch7,2", "Watch7,3", "Watch7,4", "Watch7,8", "Watch7,9"]
  for identifier in identifiers {
   precondition(NightQuality.trustedSource(product: identifier, bundle: "com.apple.health.synthetic-test", manual: false), "Authorized Watch source rejected")
   precondition(!NightQuality.trustedSource(product: identifier, bundle: "com.apple.health.synthetic-test", manual: true), "Manual source accepted")
  }
  return identifiers.count * 2
 }
}
