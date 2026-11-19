#!/usr/bin/env bash
# Builds the shared Rust core for Android and generates its Kotlin bindings.
# Outputs (git-ignored):
#   build/core-jni/<abi>/libmeitian_core.so    packaged into the APK
#   build/core-kotlin/uniffi/meitian_core/*.kt  compiled with the app
# Needs the Android NDK (ANDROID_NDK_HOME) and cargo-ndk; without them only the bindings are made.
set -euo pipefail
cd "$(dirname "$0")/.."

( cd core
  cargo build --release --lib
  cargo build --release --bin uniffi-bindgen
)
HOSTLIB=""
for f in core/target/release/libmeitian_core.dylib core/target/release/libmeitian_core.so; do
    [ -f "$f" ] && HOSTLIB=$f && break
done
rm -rf build/core-kotlin
# library mode reads cargo metadata, so run it from the crate
( cd core && target/release/uniffi-bindgen generate --library "../$HOSTLIB" --language kotlin --no-format --out-dir "../build/core-kotlin" )

if command -v cargo-ndk >/dev/null && [ -n "${ANDROID_NDK_HOME:-}" ]; then
    rustup target add aarch64-linux-android x86_64-linux-android >/dev/null
    rm -rf build/core-jni
    ( cd core && cargo ndk -t arm64-v8a -t x86_64 --platform 26 -o ../build/core-jni build --release --lib )
    find build/core-jni -name '*.so'
else
    echo "cargo-ndk / ANDROID_NDK_HOME missing: built Kotlin bindings only (no .so)"
fi
