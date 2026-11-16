# Readiness on Apple Watch Series 11

Readiness is running on a physical Series 11 using Apple’s original Cobalt interface and an independent scoring engine developed for this project. There is no HermesEnabler dependency.

![Readiness displaying 9/10 on a Series 11](https://github.com/user-attachments/assets/3501a088-4ef2-40fa-abeb-7ca09ebad09b)

The engine reads authorized sleep, resting heart rate, and heartbeat data through public HealthKit. It derives nighttime RMSSD, compares signals with prior nights, and passes its result to the native dial. The 9/10 shown above is the independent engine’s result. Apple’s original scoring, automatic daily refresh, and integration with the Health app on iPhone remain separate work.

## Try it with Xcode

Download `Readiness-Series11-Xcode.zip` from this repository, unzip it, and open `Package.swift` in Xcode. Run `ReadinessChecks` with My Mac selected to test the engine using synthetic data. The archive also includes a standalone iPhone simulator demo and instructions in `Disposicion-iPhone/README.md`.

The archive contains source for these reproducible tests. The physical Watch demo used an adapted local build of Cobalt, which is not included in this repository.
