#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build=${1:-"$root/.build-host"}
mkdir -p "$build/cache"
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
xcrun swiftc -swift-version 6 -module-cache-path "$build/cache" "$root/Engine/RobustReadinessEngine.swift" "$root/Engine/NightQuality.swift" "$root/Engine/SafeRRAccumulator.swift" "$root/Engine/ReadinessStorageCoordinator.swift" "$root/FitnessAdapter/Sources/FitnessActivityEvaluator.swift" "$root/Tests/RegressionChecks.swift" "$root/Tests/FitnessChecks.swift" "$root/Tests/ModelChecks.swift" "$root/Tests/HostMain.swift" -o "$build/checks"
"$build/checks"
