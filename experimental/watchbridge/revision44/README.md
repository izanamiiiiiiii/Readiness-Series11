# Experimental WatchBridge candidate — revision 44

The Series 9 tester successfully installed revision 42 using WatchBridge 0.1.6 but reported a host crash and a Watch profile-setup loop.

## iPhone host
The supplied crash log faults in `___UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption_block_invoke`. Revision 44 implements `UIWindowSceneDelegate`, a scene manifest, and scene-session configuration. It compiles against the installed iPhoneOS SDK. The revised host has not yet been launch-tested on an iPhone.

## Watch Health access: separate signing requirement
Age, height and weight being present in Health does not grant this app read access. The Watch app itself requests Health access; the iPhone wrapper does not read or transfer those data.

In the inspected WatchBridge 0.1.6 source (commit e8403df07d0e51c0bdebe8684974f6f22f33e340), the sideloader registers App IDs and configures App Groups but never enables the HealthKit service. Its signer uses the provisioning profile's entitlements, not the source IPA's requested entitlements. An unsigned IPA cannot add a capability absent from that profile. This is a plausible cause of the missing prompt, pending verification of the tester's actual signed Watch profile.

`check-healthkit-signing.py <SIGNED-IPA>` checks both the Watch signature and embedded provisioning profile without printing team, account or device identifiers (macOS required). The unsigned distribution IPA is expected to fail that check. A locally provisioned Watch app passes it.

`watchbridge-healthkit-proposed.patch` requests HealthKit for Watch apps declaring `NSHealthShareUsageDescription`, and fails clearly if Apple returns a profile without that capability. It applies cleanly to the inspected commit, but has NOT been compiled or tested with WatchBridge/Windows. This is a proposed upstream change, not a ready-made Windows executable. Service identifier reference: https://github.com/fastlane/fastlane/blob/master/spaceship/lib/spaceship/portal/app_service.rb

The revision 44 IPA fixes the identified host lifecycle issue only. It does not by itself fix WatchBridge's provisioning behavior. Until a signed profile is verified, use Xcode provisioning with HealthKit enabled or a signing tool that supports this capability. No Series 9/10 physical success is claimed.

The recovered Watch executable/bridge remain the build-42 baseline, with the existing generic bundle-name integration patch. Revision 43 refresh/animation work is not included in this candidate.
