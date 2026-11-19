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
