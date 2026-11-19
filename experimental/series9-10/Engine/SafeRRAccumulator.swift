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
