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
