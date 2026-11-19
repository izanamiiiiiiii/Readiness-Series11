import Foundation

// Aggregate diagnostics only: no individual beats or sample values.
struct HealthReadAudit: Codable, Sendable {
    let calculatedAt: Date
    let elapsedSeconds: Double
    let visibleSleepSamples: Int
    let trustedSleepSamples: Int
    let visibleHeartbeatSeries: Int
    let trustedHeartbeatSeries: Int
    let seriesInsideSleep: Int
    let cacheHits: Int
    let enumeratedSeries: Int
    let acceptedNights: Int
    let nightsWithRMSSD: Int
    let todayHasRMSSD: Bool
    let visibleSources: [String]
}
