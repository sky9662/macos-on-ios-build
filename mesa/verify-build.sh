#!/usr/bin/env bash
set -euo pipefail
recipe="$1"
out="$2"
test ! -e "$out"
mkdir -p "$out/libraries" "$out/licenses" "$out/source-recipes"
for name in libOSMesa libMoltenVK; do
  src="$recipe/app/Madeira/gl/$name.dylib"
  test -s "$src"
  xcrun lipo -verify_arch arm64 "$src"
  xcrun vtool -show-build "$src" | tee "$out/$name.platform.txt"
  grep -iE 'platform[[:space:]]+IOS([[:space:]]|$)' "$out/$name.platform.txt"
  xcrun otool -L "$src" | tee "$out/$name.dependencies.txt"
  xcrun nm -gUj "$src" > "$out/$name.exports.txt"
  cp "$src" "$out/libraries/"
  cp "$recipe/app/Madeira/gl/$name.version" "$out/"
done
for sym in OSMesaCreateContextAttribs OSMesaMakeCurrent OSMesaGetProcAddress OSMesaDestroyContext OSMesaGetCurrentContext; do
  grep -Fx "_$sym" "$out/libOSMesa.exports.txt"
done
for sym in vkGetInstanceProcAddr vkGetDeviceProcAddr; do
  grep -Fx "_$sym" "$out/libMoltenVK.exports.txt"
done
# Validate an independently written, compile-only native consumer of the public API.
# This does not run iOS code on the Mac CI runner.
xcrun --sdk iphoneos clang -target arm64-apple-ios17.0 -std=c11 -Wall -Wextra -Werror \
  -c mesa/osmesa-consumer.c -o "$out/osmesa-consumer.o"
xcrun lipo -verify_arch arm64 "$out/osmesa-consumer.o"
xcrun nm -u "$out/osmesa-consumer.o" | grep -F _OSMesaMakeCurrent
xcrun --sdk iphoneos clang -target arm64-apple-ios17.0 -dynamiclib \
  "$out/osmesa-consumer.o" "$out/libraries/libOSMesa.dylib" \
  -install_name @rpath/libTCMesaConsumer.dylib -o "$out/libTCMesaConsumer.dylib"
xcrun otool -L "$out/libTCMesaConsumer.dylib" | grep -F @rpath/libOSMesa.dylib
# Preserve notices and exact publicly available corresponding build sources.
cp "$recipe/app/Madeira/licenses/Mesa-license.rst" "$out/licenses/"
for f in MoltenVK-Apache-2.0.txt SPIRV-Cross-Apache-2.0.txt SPIRV-Tools-Apache-2.0.txt cereal-BSD-3-Clause.txt; do
  cp "$recipe/app/Madeira/licenses/$f" "$out/licenses/"
done
for f in LICENSE LICENSE-BCD.md LICENSE-EXCEPTION.md THIRD-PARTY-NOTICES.md; do
  cp "$recipe/$f" "$out/licenses/BCD-$f"
done
cp -R "$recipe/build/mesa-ios/patches" "$out/source-recipes/"
cp "$recipe/build/mesa-ios/build.sh" "$out/source-recipes/build-mesa.sh"
cp "$recipe/build/mesa-ios/ios-arm64.cross" "$out/source-recipes/"
cp "$recipe/build/mesa-ios/kk-stale-source.sh" "$out/source-recipes/"
cp "$recipe/build/moltenvk-ios/build.sh" "$out/source-recipes/build-moltenvk.sh"
cp mesa/SOURCES.md "$out/"
(cd "$out" && shasum -a 256 libraries/*.dylib > SHA256SUMS)
echo "Verified ARM64 iOS libraries and consumer link. No device rendering tested."
