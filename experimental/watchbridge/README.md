> **Tester report (21 Nov):** Both apps install on Series 9 with WatchBridge 0.1.6, but this original candidate's iPhone host crashes and the Watch app stays at profile setup without a Health prompt. Do not treat it as a working release. [Revision 44 investigation and source fixes](revision44/README.md) document the host lifecycle fix and separate HealthKit provisioning requirement. The proposed WatchBridge patch and revised host still need device/Windows validation.

# Generic iPhone host for WatchBridge — EXPERIMENTAL / UNTESTED INSTALLATION

The iPhone host is implemented and compiled. The IPA contains `Payload/ReadinessHost.app/Watch/Readiness.app`, with the companion relationship configured.

[Download unsigned generic candidate](Readiness-WatchBridge-generic-EXPERIMENTAL-unsigned.ipa?raw=true) · [Builder source](WatchBridge-generic-host-source.zip?raw=true) · [Manifest](Readiness-WatchBridge-generic-EXPERIMENTAL-unsigned.json)

## Generic signing

This candidate does **not** require our Apple account, team or device. Sign it with your own account through WatchBridge. WatchBridge changes the bundle identifiers to include your team. The recovered bridge originally rejected a different bundle identifier; this generic candidate removes that one integration-name guard in the known bridge so that a team-specific rebuild is not needed. No private entitlements are added, and HealthKit authorization is still required. The host and Watch apps remain linked when WatchBridge rewrites their identifiers.

The builder verifies the exact build42 baseline SHA-256 and original instructions before making the four-byte change. All other integration code is retained. Static checks cover ZIP integrity, host executable, companion layout, absence of provisioning profiles/signatures, and identifier rewrite cases for three independent team IDs. These are package checks, not installation tests.

## What remains unverified

**End-to-end signing, installation, launch and data access through WatchBridge are not confirmed.** A local Xcode provisioning attempt stopped at the Apple account limit of 10 new App IDs per seven days. The earlier team-specific Watch target signed; the host profile was blocked. That earlier signing success does not validate this new generic candidate. We have not replaced the working installation with this test.

The complete Watch payload requires watchOS27.3 and was derived from the Series11 adaptation tested with 27.3 beta2 (24S5296d). Series9/10 and other OS builds remain experimental. This host change does not establish their hardware compatibility. The account/device registration, development-mode, signing limits and profiles required by the installer still apply.

## Please report your result

Please let us know whether it signs, installs on the iPhone, transfers to the paired Watch, opens, and displays a result from current authorized data. Include Watch model, exact watchOS build, WatchBridge version, and the stage/error if it fails. Do not share account credentials, certificates, private keys, provisioning profiles or health data.

## Is Xcode the only option?

No. [WatchBridge](https://github.com/AdminZachary/WatchBridge) supports companion installation on Windows, Linux and macOS. Xcode is the route used for this project so far. The generic host is intended to enable the WatchBridge route; it remains unverified for this app until a tester reports installation and launch.

To regenerate on macOS with Xcode installed:

```sh
python3 build-generic.py --base-ipa Readiness-Series11-build42-Fitness-sin-firma.ipa
python3 verify-generic.py
```

The baseline is available under `backups/build42/` in this repository. The source and manifest document the exact patch; this is not a complete source rebuild of Cobalt or the build38 bridge.
