import Foundation
@main struct HostChecks {
 @MainActor static func main() async throws {
  let engine = try await RegressionChecks.run()
  let fitness = FitnessChecks.run()
  let models = ModelChecks.run()
  print("TOTAL \(engine + fitness + models) checks passed (engine \(engine), fitness \(fitness), source model checks \(models)); synthetic inputs only")
 }
}
