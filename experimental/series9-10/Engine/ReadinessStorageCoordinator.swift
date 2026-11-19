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
