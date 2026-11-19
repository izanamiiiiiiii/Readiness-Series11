# Fitness integration, build 42

Tested on a physical Series 11 with watchOS 27.3 beta 2. The running app displayed its independent readiness score and availability checks for Fitness, Vitals and Sleep.

The added Fit.framework reads authorized daily activity summaries through public HealthKit. It supplements a missing activity contribution in our own scoring model using yesterday's observed active energy and a baseline of at least five valid days. Missing records remain unavailable. It requests no write access. The experimental activity weight is 15%; this is not Apple's readiness algorithm.

The framework also corrects the recovered bridge's assumption that dyld image zero is the executable during an Xcode launch. It resolves the executable's actual __TEXT slide, scoped to calls from ReadinessBridge. The existing recovered engine and original UI remain in the package. Twelve synthetic evaluator checks pass.

Files:
- Readiness-Series11-build42-Fitness-sin-firma.ipa: recoverable watch-only app; requires your own valid Xcode development signature and provisioning.
- ../../sources/Readiness-Fitness-build42-source.zip: new adapter source and build script.
- manifest.json: package hash and observed validation.

The full build38 source remains unavailable. Keep its original backup and the build30 source archive as well. Private provisioning, signing keys, device data containers and health diagnostics are excluded. Long-term/background refresh and every Fitness detail view have not been validated.
