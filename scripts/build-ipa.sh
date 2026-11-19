#!/usr/bin/env bash
# Builds an unsigned Meitian.ipa. Needs macOS with Xcode and XcodeGen
# (brew install xcodegen); GitHub Actions does this in .github/workflows/ios.yml.
#
# The .ipa is unsigned: sign it while installing with Sideloadly, AltStore or
# SideStore (free Apple ID), or install it as-is with TrollStore.
set -euo pipefail
cd "$(dirname "$0")/.."

BUILD=${GITHUB_RUN_NUMBER:-1}
mkdir -p build
scripts/build-core-ios.sh
xcodegen generate

xcodebuild \
  -project Meitian.xcodeproj -scheme Meitian -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build/dd \
  CURRENT_PROJECT_VERSION="$BUILD" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  build | tee build/xcodebuild.log | grep -E "error:|warning: .*Meitian/|BUILD (SUCCEEDED|FAILED)" || true
grep -q "BUILD SUCCEEDED" build/xcodebuild.log

APP=build/dd/Build/Products/Release-iphoneos/Meitian.app
rm -rf build/Payload && mkdir -p build/Payload
cp -R "$APP" build/Payload/
# ad-hoc signature keeps the binary well-formed; sideloading tools re-sign it
codesign --force --sign - --timestamp=none build/Payload/Meitian.app 2>/dev/null || true
(cd build && rm -f Meitian.ipa && zip -qry Meitian.ipa Payload)
echo "built build/Meitian.ipa ($(du -h build/Meitian.ipa | cut -f1))"
