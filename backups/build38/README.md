# Recovered Readiness build 38

This is the Series 11 adaptation recovered from the existing development installation, not the small Readiness 1.1 build 9 package from the App Store.

## Preserved components

- Cobalt executable, originally 479,664 bytes before signature removal.
- ReadinessBridge.framework/ReadinessBridge, originally 1,732,320 bytes before signature removal.
- Assets.car, localization resources and Info.plist.
- Bundle ID: cl.moisesretamal.ReadinessAuthenticUIProbe.watchkitapp.
- Version 1.0, build 38, minimum watchOS 27.3.

Cobalt has no active encryption load command and ReadinessBridge declares cryptid 0. Recovery did not decrypt an App Store binary. The author's original signed IPA is retained locally; only the version without personal provisioning profiles and code signatures is published.

## Check the download

Use `shasum -a 256 Readiness-Series11-build38-sin-firma.ipa` and compare the result with manifest.json. The ZIP was integrity-checked. The Cobalt and bridge __text sections were compared before and after signature removal and are unchanged. No health samples, app data containers, Apple account credentials, private signing keys, or provisioning profiles are included.

## Sign and install

This is a watch-only package. Unzip it to obtain Payload/Readiness.app. Use a valid Apple development identity and a watchOS development provisioning profile authorizing your Watch, the bundle identifier and the public HealthKit entitlement. Review the final entitlements against that profile. Sign embedded frameworks first, then the containing app, using your own profile and identity. Do not add private HealthKit entitlements to an ordinary development profile.

Keep the current installed app and its data until a newly signed copy is verified. Do not blindly change the bundle identifier: the bridge has identifier-dependent behavior. Do not assume an iPhone IPA installer supports this watch-only layout. Install a correctly signed Watch app through Xcode/Device Hub or devicectl. No reinstallation test was performed during recovery.

## Modifying it later

The executable and embedded bridge can now be inspected and modified, but there is no recovered complete build 38 Swift source tree. The source ZIP under sources/ is build 30. Its prepare-app.py accepts a specific earlier input hash; do not run it blindly against build 38 or disable its guard to make it accept another binary.

Always retain the recovered baseline and save new versions under new names, with hashes, supported watchOS build, signing requirements and observed checks.
