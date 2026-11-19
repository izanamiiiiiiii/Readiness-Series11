#!/bin/sh
set -eu
adapter_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
build_dir=${1:-"$adapter_root/build"}
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
sdk=$(xcrun --sdk watchos --show-sdk-path)
mkdir -p "$build_dir/cache"
xcrun clang -fblocks -target arm64e-apple-watchos27.3 -isysroot "$sdk" -c "$adapter_root/Sources/FitnessInterpose.c" -o "$build_dir/FitnessInterpose.o"
xcrun clang -target arm64e-apple-watchos27.3 -isysroot "$sdk" -c "$adapter_root/Sources/MainImageSlide.c" -o "$build_dir/MainImageSlide.o"
xcrun swiftc -target arm64e-apple-watchos27.3 -sdk "$sdk" -swift-version 6 -parse-as-library -emit-library -module-name FitnessSummaryAdapter -module-cache-path "$build_dir/cache" -I "$adapter_root/Modules" "$adapter_root"/Sources/*.swift "$build_dir/FitnessInterpose.o" "$build_dir/MainImageSlide.o" -framework HealthKit -Xlinker -undefined -Xlinker dynamic_lookup -Xlinker -install_name -Xlinker @executable_path/Frameworks/Fit.framework/Fit -o "$build_dir/Fit"
