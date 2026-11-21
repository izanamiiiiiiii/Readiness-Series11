# Readiness host + HealthKit setup fix — revision 45

[Download unsigned IPA](Readiness-Host45-HealthKit-EXPERIMENTAL-unsigned.ipa?raw=true) · [Source](source.zip?raw=true) · [Manifest](manifest.json) · [Download corrected Windows installer](https://github.com/izanamiiiiiiii/Readiness-Series11/releases/download/readiness-host45-healthkit-experimental/Readiness-WatchBridge-HealthKit-Windows.zip) · [Successful Windows build](https://github.com/izanamiiiiiiii/Readiness-Series11/actions/runs/44931917761)

This revision addresses the two failures reported with WatchBridge 0.1.6: the iPhone host terminating on launch, and Watch setup remaining at age/height/weight without a Health authorization prompt. Series 9/10 end-to-end testing is still required; this is an experimental candidate, not a confirmed hardware compatibility release.

## What changed

- The iPhone host now implements the UIKit scene lifecycle required by the tester's OS. The supplied crash log faults in `___UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption_block_invoke`.
- The host includes a real **Allow access to Health** button requesting read-only date of birth, height and body mass, plus **Check profile again**. It reports availability without storing or uploading measurements. Request completion is not treated as proof of read permission; actual HealthKit reads determine availability. It does not ask users to re-enter existing records.
- Both host and Watch declare their Health read purpose. The Watch payload retains its public-profile bridge and its own Health authorization request.
- The included installer patch enables Apple's HealthKit service for each host/Watch App ID that declares public Health read access. It then checks both resulting provisioning profiles and refuses to sign a nonfunctional package if HealthKit was not granted. This handles existing App IDs too. It does not fabricate entitlements or bypass Apple's profiles or user consent.

## Install with the corrected signer

1. Download this IPA and the corrected Windows installer ZIP linked above. The executable is a modified WatchBridge 0.1.6 build; see [attribution and provenance](INSTALLER-NOTICE.txt). If no successful build/artifact is shown, use the source patch to build it or use Xcode with HealthKit enabled for **both** targets.
2. Sign/install using your own Apple account. The existing unmodified WatchBridge 0.1.6 executable is not sufficient for the capability fix; updating the IPA alone does not change how it provisions App IDs.
3. Open Readiness Host on iPhone, tap **Allow access to Health**, and enable age, height, and weight. Check that the three fields are available. The host checks iPhone data; it does not transfer a profile to Watch.
4. Open Readiness on the Watch and grant its Health read permissions. Reopen the Watch app after granting if its initial setup screen remains visible. The Watch needs its own authorized profile and sleep/activity history; an iPhone availability check alone does not prove Watch access.

No credentials, certificates, private profiles or health data are included. The unsigned candidate is independent of our team/device; each user signs with their own account. The existing generic bundle-ID integration patch is preserved. The recovered Watch baseline is build42 (watchOS27.3); the separate build43 animation experiment is not included.

## Validation

- Host compiled for physical iOS and development-signed temporary test copy provisioned with HealthKit for local device testing. The public IPA is unsigned. Device launch/permission verification is tracked separately from compilation.
- Installer capability change compiled; all **19 isideload library tests passed**, including new tests rejecting absent/false/nonboolean HealthKit grants and verifying capability detection.
- ZIP integrity, nested companion structure, native host executable, bundle-ID rewrites for three independent teams, exact recovered bridge patch, and absence of private profiles/signatures passed.
- `check-healthkit-signing.py <SIGNED-IPA>` checks signature **and** profile grants for both host and Watch on macOS. The unsigned distribution package is expected to fail that check. Do not post signed profiles or health data in issues.
- Windows build **succeeded**: 142 application tests and 19 signing-library tests passed (161 total). Executable SHA-256: `a161d205af2ccc131d2abc9f039868ba0970923cb9698f5d1cb32401cf0e32a9`. Archive SHA-256: `607fa61210cac75dc52d4dbff3036e6f6f54b5854173ba741ce5fe0648434594`. The permanent experimental release preserves the original artifact, notices and licences.
- Windows build and physical Series9/10 results are independent validation stages. A passing build does not claim physical setup success. Original upstream: https://github.com/AdminZachary/WatchBridge (pinned e8403df07d0e51c0bdebe8684974f6f22f33e340).

Rebuild the app using `build-generic.py --base-ipa Readiness-Series11-build42-Fitness-sin-firma.ipa` and run `verify-generic.py`. Apply `watchbridge-healthkit.patch` to the pinned WatchBridge source and build with its documented platform script. Preserve `src-tauri/Cargo.lock`; building the vendored crate as a separate project can resolve incompatible upstream revisions.

Apple references: [HealthKit authorization](https://developer.apple.com/documentation/healthkit/authorizing-access-to-health-data), [HealthKit capability](https://developer.apple.com/documentation/xcode/configuring-healthkit-access).
