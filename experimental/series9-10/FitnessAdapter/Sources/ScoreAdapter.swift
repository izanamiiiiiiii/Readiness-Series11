import Foundation
import WorkoutCore

extension WorkoutCore.ReadinessScoreModel {
    /// Matches the native value initializer's Swift calling convention.
    /// Applies only to the own-engine result when its activity contribution is absent.
    @_silgen_name("fitness_summary_score_init")
    public init(fitnessSummaryScore score: Double?, scaledScore: Int?, category: ReadinessCategory?,
                activityComponent: Double?, activityDrivingFactor: WOReadinessActivityFactor?,
                vitalsComponent: Double?, overnightVitalsComponent: Double?, overnightVitalsSubscores: [WORecoverySubscore]?,
                daytimeVitalsComponent: Double?, sleepScoreComponent: Double?, sleepSubscores: [WORecoverySubscore]?,
                algorithmVersion: String?, sleepScoreComparison: SleepScoreComparison?) {
        guard activityComponent == nil, let originalScore = score, originalScore.isFinite,
              (-1...1).contains(originalScore), algorithmVersion?.contains("normalized-native-presentation") == true,
              let input = FitnessValueStore.current() else {
            self.init(score: score, scaledScore: scaledScore, category: category, activityComponent: activityComponent,
                activityDrivingFactor: activityDrivingFactor, vitalsComponent: vitalsComponent,
                overnightVitalsComponent: overnightVitalsComponent, overnightVitalsSubscores: overnightVitalsSubscores,
                daytimeVitalsComponent: daytimeVitalsComponent, sleepScoreComponent: sleepScoreComponent,
                sleepSubscores: sleepSubscores, algorithmVersion: algorithmVersion, sleepScoreComparison: sleepScoreComparison)
            return
        }
        let weight = 0.15
        let component = weight * input.normalizedActivity
        let combined = max(-1, min(1, (1 - weight) * originalScore + component))
        let scaled = ReadinessCategory.scaledScore(from: combined)
        let classification: ReadinessActivityClassification = input.yesterdayEnergyKcal > input.baselineMedianKcal * 1.1 ? .above :
            input.yesterdayEnergyKcal < input.baselineMedianKcal * 0.9 ? .below : .steady
        let factor = WOReadinessActivityFactor(component: .yesterdayCalories, score: input.normalizedActivity, classification: classification)
        self.init(score: combined, scaledScore: scaled, category: scaled.map(ReadinessCategory.category(for:)),
            activityComponent: component, activityDrivingFactor: factor,
            vitalsComponent: vitalsComponent.map { $0 * (1 - weight) },
            overnightVitalsComponent: overnightVitalsComponent.map { $0 * (1 - weight) },
            overnightVitalsSubscores: overnightVitalsSubscores,
            daytimeVitalsComponent: daytimeVitalsComponent.map { $0 * (1 - weight) },
            sleepScoreComponent: sleepScoreComponent.map { $0 * (1 - weight) }, sleepSubscores: sleepSubscores,
            algorithmVersion: (algorithmVersion ?? "") + ".fitness-summary-v1", sleepScoreComparison: sleepScoreComparison)
    }
}
