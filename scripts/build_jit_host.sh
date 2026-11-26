#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"
ZIP="$(mktemp -d)/StikJIT.xcframework.zip"
trap 'rm -rf "$(dirname "$ZIP")"' EXIT
curl --fail --location --retry 3 --output "$ZIP" 'https://github.com/StikDebug/StikJIT/releases/download/2.0.1/StikJIT.xcframework.zip'
echo "c376687326a785f5ed1da8caca08adc709b56919019dd751bca059b92b175d95  $ZIP" | shasum -a 256 -c -
test ! -e jit/StikJIT.xcframework
unzip -q "$ZIP" -d jit
test -f jit/StikJIT.xcframework/Info.plist
plutil -lint jit/StikJIT.xcframework/Info.plist
command -v xcodegen >/dev/null || brew install xcodegen
# Generate the project before running expensive compiler checks.
(cd jit && xcodegen generate --spec project.yml)
# Execute pairing validation regressions on the macOS runner, no device or real secrets.
xcrun --sdk macosx swiftc jit/Shared/Contract.swift jit/Tests/main.swift -o "$RUNNER_TEMP/tc-pairing-tests"
"$RUNNER_TEMP/tc-pairing-tests"
cd jit
# Compile the full helper/host; no stub target or disabled regression.
xcodebuild -project TCJITHost.xcodeproj -list
xcodebuild -project TCJITHost.xcodeproj -scheme TCJITHost -configuration Release -destination 'generic/platform=iOS' -derivedDataPath "$RUNNER_TEMP/tc-jit-build" CODE_SIGNING_ALLOWED=NO build
APP="$RUNNER_TEMP/tc-jit-build/Build/Products/Release-iphoneos/TCJITHost.app"
test -f "$APP/TCJITHost"
HELPER="$(find "$APP" -type d -name TCJITHelper.appex -print -quit)"
test -n "$HELPER"
test -f "$HELPER/TCJITHelper"
xcrun lipo -verify_arch arm64 "$HELPER/TCJITHelper"
xcrun otool -L "$HELPER/TCJITHelper" | grep -F StikJIT.framework
if xcrun otool -L "$APP/TCJITHost" | grep -F StikJIT.framework; then
  echo 'Host must not link StikJIT' >&2; exit 1
fi
test -n "$(find "$APP" -type f -path '*/StikJIT.framework/StikJIT' -print -quit)"
plutil -lint "$APP/Info.plist" "$HELPER/Info.plist"
# Classic extension must be in PlugIns for sideloaders to find and re-sign.
test -f "$APP/PlugIns/TCJITHelper.appex/TCJITHelper"
test ! -e "$APP/Extensions/TCJITHost.appexpt"
python3 - "$APP" <<'PY'
import pathlib, plistlib, sys
app=pathlib.Path(sys.argv[1])
host=plistlib.loads((app/"Info.plist").read_bytes())
helper=plistlib.loads((app/"PlugIns/TCJITHelper.appex/Info.plist").read_bytes())
assert helper["CFBundleIdentifier"].startswith(host["CFBundleIdentifier"]+".")
assert helper["NSExtension"]["NSExtensionPointIdentifier"] == "com.apple.ar.viewer"
assert helper["NSExtension"]["NSExtensionPrincipalClass"] == "TCClassicHelperHandler"
print("Classic helper PlugIns layout, host prefix and principal class verified")
PY
# Package a distinct unsigned diagnostic, not game code; do not sign in CI.
xcrun lipo -verify_arch arm64 "$APP/TCJITHost"
test ! -e "$APP/embedded.mobileprovision"
test -z "$(find "$APP" -name embedded.mobileprovision -o -name pairingFile.plist -o -name pairing.plist)"
STAGE="$(mktemp -d)"
mkdir -p "$STAGE/Payload"
ditto "$APP" "$STAGE/Payload/TCJITHost.app"
cp "$ROOT/licenses/StikJIT-MPL-2.0.txt" "$STAGE/Payload/TCJITHost.app/STIKJIT-LICENSE.txt"
(cd "$STAGE" && zip -qry "$ROOT/TCJITReadiness-unsigned.ipa" Payload)
unzip -t "$ROOT/TCJITReadiness-unsigned.ipa"
python3 "$ROOT/scripts/check_jit_ipa.py" "$ROOT/TCJITReadiness-unsigned.ipa"
rm -rf "$STAGE"

