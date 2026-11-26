#!/usr/bin/env bash
set -euo pipefail
kit="$(cd "$1" && pwd)"
up="$(cd "$2" && pwd)"
export T="$RUNNER_TEMP/tc-mesa-mac-build"
out="$RUNNER_TEMP/tc-mesa-package"
(cd "$kit" && shasum -a 256 -c SHA256SUMS)
test "$(cat "$kit/libOSMesa.version")" = mesa-25.0.7
test "$(cat "$kit/libMoltenVK.version")" = v1.4.2
mkdir -p "$T"
for pair in "libOSMesa MesaCore" "libMoltenVK MoltenVK"; do
  read -r source name <<< "$pair"
  fw="$T/$name.framework";mkdir "$fw"
  cp "$kit/libraries/$source.dylib" "$fw/$name"
  xcrun lipo -verify_arch arm64 "$fw/$name"
  xcrun install_name_tool -id "@rpath/$name.framework/$name" "$fw/$name"
  plutil -create xml1 "$fw/Info.plist"
  plutil -insert CFBundleExecutable -string "$name" "$fw/Info.plist"
  plutil -insert CFBundleIdentifier -string "com.sky9662.tcmesadiagnostics.$name" "$fw/Info.plist"
  plutil -insert CFBundlePackageType -string FMWK "$fw/Info.plist"
  plutil -insert CFBundleVersion -string 1 "$fw/Info.plist"
  plutil -insert CFBundleShortVersionString -string 1.0 "$fw/Info.plist"
  plutil -insert MinimumOSVersion -string 17.0 "$fw/Info.plist"
  plutil -lint "$fw/Info.plist"
done
# Separate re-export umbrella preserves Mac GL imports while overriding
# only default-buffer selection. All other GL functions remain Mesa-native.
xcrun --sdk macosx clang -std=c11 -Wall -Wextra -Werror mesa/context/test-pixel-format.c -o "$T/test-pixel-format"
"$T/test-pixel-format"
mkdir "$T/OpenGLShim.framework"
xcrun --sdk iphoneos clang -target arm64-apple-ios17.0 -std=c11 -Wall -Wextra -Werror -dynamiclib \
  -install_name @rpath/OpenGLShim.framework/OpenGLShim \
  -Wl,-reexport_library,"$T/MesaCore.framework/MesaCore" \
  mesa/context/desktop-gl.c -o "$T/OpenGLShim.framework/OpenGLShim"
cp "$T/MesaCore.framework/Info.plist" "$T/OpenGLShim.framework/Info.plist"
plutil -replace CFBundleExecutable -string OpenGLShim "$T/OpenGLShim.framework/Info.plist"
plutil -replace CFBundleIdentifier -string com.apple.opengl "$T/OpenGLShim.framework/Info.plist"
# GLFW looks up this exact identifier, not a custom diagnostic identifier.
test "$(plutil -extract CFBundleIdentifier raw "$T/OpenGLShim.framework/Info.plist")" = com.apple.opengl
xcrun otool -l "$T/OpenGLShim.framework/OpenGLShim" | grep -A4 LC_REEXPORT_DYLIB | grep -F @rpath/MesaCore.framework/MesaCore
xcrun nm -gUj "$T/MesaCore.framework/MesaCore" > "$T/gl-exports.txt"
xcrun nm -gUj "$T/OpenGLShim.framework/OpenGLShim" > "$T/gl-overrides.txt"
for s in glDrawBuffer glReadBuffer glDrawBuffers; do grep -Fx "_$s" "$T/gl-overrides.txt"; done
cp mesa/context/pixel-format.h "$up/shim/overrides/TCMesaPixelFormat.h"
for s in OSMesaCreateContextAttribs OSMesaMakeCurrent OSMesaPixelStore OSMesaGetProcAddress glTexBuffer glPolygonMode glDrawElementsBaseVertex glShaderSource glGetString glFinish; do
  grep -Fx "_$s" "$T/gl-exports.txt"
done
python3 mesa/context/prepare.py "$up"
export UDID=compile-only TEAM=compile-only IDENTITY=compile-only
bash -n "$up/probe/build.sh"
(cd "$up/probe" && bash build.sh mac shim)
xcrun otool -L "$T/AppKitShim.framework/AppKitShim" | grep -F @rpath/OpenGLShim.framework/OpenGLShim
xcrun otool -L "$T/AppKitShim.framework/AppKitShim" | grep -F IOSurface.framework/IOSurface
if xcrun otool -L "$T/AppKitShim.framework/AppKitShim" | grep -F OpenGLES.framework; then exit 1; fi
xcrun nm -u "$T/MacProbe.app/Contents/MacOS/MacProbe" | awk '{print $NF}' | grep '^_gl' | sort -u > "$T/mac-gl-imports.txt"
while IFS= read -r symbol; do grep -Fx "$symbol" "$T/gl-exports.txt"; done < "$T/mac-gl-imports.txt"
python3 scripts/package_mac_probe.py "$T" "$up" "$out" --diagnostics
app="$out/Payload/MacProbe.app"
cp -R "$T/MoltenVK.framework" "$T/MesaCore.framework" "$app/Frameworks/"
codesign --remove-signature "$app/Frameworks/MesaCore.framework/MesaCore"
codesign --remove-signature "$app/Frameworks/MoltenVK.framework/MoltenVK"
# Preserve the installed TC Diagnostics identity across renderer upgrades.
test "$(plutil -extract CFBundleIdentifier raw "$app/Info.plist")" = com.sky9662.tcdiagnostics
plutil -replace CFBundleDisplayName -string "TC Mesa" "$app/Info.plist"
mkdir -p "$app/ThirdParty"
cp -R "$kit/licenses" "$kit/source-recipes" "$kit/SOURCES.md" "$kit/SHA256SUMS" "$app/ThirdParty/"
cp mesa/SOURCES.md "$app/ThirdParty/INTEGRATION.md"
test ! -e "$app/embedded.mobileprovision"
test "$(plutil -extract CFBundleIdentifier raw "$app/Frameworks/OpenGLShim.framework/Info.plist")" = com.apple.opengl
xcrun otool -L "$app/MacProbe" | grep -F @rpath/OpenGLShim.framework/OpenGLShim
xcrun vtool -show-build "$app/Frameworks/MoltenVK.framework/MoltenVK" | grep -i 'platform IOS'
(cd "$out" && zip -qry "$GITHUB_WORKSPACE/TCMesaDiagnostics-unsigned.ipa" Payload)
unzip -t TCMesaDiagnostics-unsigned.ipa

# Validate the actual distributed IPA, not just the staging directory.
python3 - TCMesaDiagnostics-unsigned.ipa <<'PY'
import plistlib, sys, zipfile
with zipfile.ZipFile(sys.argv[1]) as archive:
    info = plistlib.loads(archive.read("Payload/MacProbe.app/Info.plist"))
    if info["CFBundleIdentifier"] != "com.sky9662.tcdiagnostics":
        raise SystemExit("Diagnostic app bundle identifier changed")
PY
