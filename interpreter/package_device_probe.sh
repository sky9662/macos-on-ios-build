#!/bin/bash
set -euo pipefail
root="$(cd "$1" && pwd)"
build="$(cd "$2" && pwd)"
out="$3"
repo="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$out/Payload/TCVIXLProbe.app"
out="$(cd "$out" && pwd)"
app="$out/Payload/TCVIXLProbe.app"
target=arm64-apple-ios17.0
xcrun --sdk iphoneos clang++ -target "$target" -std=c++17 -O2 -DNDEBUG -DTC_DEVICE_PROBE -DVIXL_INCLUDE_TARGET_A64 -DVIXL_INCLUDE_SIMULATOR_AARCH64 -DVIXL_CODE_BUFFER_MALLOC -I"$root/src" -c "$repo/interpreter/vixl_reference.cc" -o "$out/reference.o"
xcrun --sdk iphoneos clang -target "$target" -fobjc-arc -c "$repo/interpreter/device_probe.m" -o "$out/app.o"
xcrun --sdk iphoneos clang++ -target "$target" "$out/app.o" "$out/reference.o" "$build/iphoneos/subset.o" "$build/iphoneos/libvixl.a" -framework UIKit -framework Foundation -o "$app/TCVIXLProbe"
cat > "$app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.sky9662.tcvixlprobe</string>
<key>CFBundleExecutable</key><string>TCVIXLProbe</string>
<key>CFBundleName</key><string>TC VIXL Probe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>MinimumOSVersion</key><string>17.0</string>
<key>UIDeviceFamily</key><array><integer>1</integer><integer>2</integer></array>
<key>UILaunchScreen</key><dict/>
</dict></plist>
PLIST
cp "$root/LICENCE" "$app/VIXL-LICENCE"
plutil -lint "$app/Info.plist"
xcrun lipo -verify_arch arm64 "$app/TCVIXLProbe"
xcrun vtool -show-build "$app/TCVIXLProbe" | grep -i 'platform IOS'
xcrun nm -u "$app/TCVIXLProbe" > "$out/imports.txt"
if grep -E 'pthread_jit_write|MAP_JIT' "$out/imports.txt"; then exit 1; fi
(cd "$out" && zip -qr tc-vixl-probe.ipa Payload && shasum -a 256 tc-vixl-probe.ipa > tc-vixl-probe.ipa.sha256)
