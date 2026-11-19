#!/usr/bin/env bash
# Builds the shared Rust core for iPhone and generates its Swift bindings.
# Outputs (git-ignored):
#   core/target/aarch64-apple-ios/release/libmeitian_core.a   linked into the app
#   build/core-swift/meitian_core.swift                         compiled with the app
#   build/core-include/{meitian_coreFFI.h,module.modulemap}    C header the Swift file imports
set -euo pipefail
cd "$(dirname "$0")/.."

export IPHONEOS_DEPLOYMENT_TARGET=17.0
# aarch64-apple-ios for devices, aarch64-apple-ios-sim for the simulator smoke test
TARGET=${CORE_TARGET:-aarch64-apple-ios}
rustup target add "$TARGET" >/dev/null

( cd core
  cargo build --release --lib --target "$TARGET"
  # bindings are generated from a host build of the same library
  cargo build --release --lib
  cargo build --release --bin uniffi-bindgen
)

HOSTLIB=""
for f in core/target/release/libmeitian_core.dylib core/target/release/libmeitian_core.so; do
    [ -f "$f" ] && HOSTLIB=$f && break
done
rm -rf build/core-swift build/core-include build/core-lib
mkdir -p build/core-swift build/core-include build/core-lib
# Only the static library goes where the app links from. Cargo also builds a .dylib (the cdylib
# Android needs); if the linker saw it, the app would look for it at a build-machine path and die
# at launch with "Library not loaded".
cp "core/target/$TARGET/release/libmeitian_core.a" build/core-lib/
# library mode reads cargo metadata, so run it from the crate
( cd core && target/release/uniffi-bindgen generate --library "../$HOSTLIB" --language swift --no-format --out-dir "../build/core-gen" )
mv build/core-gen/meitian_core.swift build/core-swift/
mv build/core-gen/meitian_coreFFI.h build/core-include/
mv build/core-gen/meitian_coreFFI.modulemap build/core-include/module.modulemap
rm -rf build/core-gen
echo "core ready: $(du -h build/core-lib/libmeitian_core.a | cut -f1) static lib ($TARGET)"
