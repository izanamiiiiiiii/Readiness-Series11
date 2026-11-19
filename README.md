# Readiness on Apple Watch Series 11

Readiness uses Apple's original Cobalt interface and an independent scoring engine for Series 11. There is no HermesEnabler dependency. The score is our experimental result, not Apple's readiness algorithm.

## Recovered build 38 backup

The actual app installed on the author's Watch was recovered through Xcode/LLDB on November 19, 2026. Its Cobalt executable, ReadinessBridge.framework, assets and localization files are now preserved here.

- [Download recovered build 38, unsigned IPA](backups/build38/Readiness-Series11-build38-sin-firma.ipa?raw=true)
- [Recovery and signing notes](backups/build38/README.md)
- [Hashes and recovery manifest](backups/build38/manifest.json)
- [Earlier build 30 bridge and engine source](sources/Readiness-Series11-build30-source.zip?raw=true)
- [Earlier Xcode engine test kit](https://github.com/izanamiiiiiiii/Readiness-Series11/releases/tag/xcode-demo-v1)

The build 38 backup is a recovered binary, not a complete source project. The build 30 ZIP contains earlier engine and integration source; it does not reproduce every build 38 change. Preserve both. The unsigned backup removes personal provisioning profiles and signatures while preserving each executable's machine-code section byte for byte. It needs a new, valid development signature before installation. Reinstallation of this backup has not been tested.

The engine reads authorized sleep, resting heart rate, and heartbeat data through public HealthKit, derives nighttime RMSSD and compares signals with prior nights. Availability depends on real inputs and history. Background refresh, stability and the Sleep/Fitness detail models remain experimental.

![Earlier physical Series 11 demonstration](https://github.com/user-attachments/assets/3501a088-4ef2-40fa-abeb-7ca09ebad09b)

## Earlier reproducible engine checks

Download the Xcode kit from the v1 release, unzip it, and open Package.swift. Run ReadinessChecks on My Mac with synthetic inputs. This kit's independent iPhone simulator demo is separate from the recovered Cobalt Watch app.

## Recovery rule

Keep binary backups, source archives, manifests and recovery instructions in version control before replacing an installed build. A repository URL alone is not a backup unless its actual packages are present. Device containers and health diagnostics are deliberately excluded from this repository.

Apple software and assets remain Apple's property. This repository is not affiliated with Apple; the recovered binary is not relicensed as project source.
