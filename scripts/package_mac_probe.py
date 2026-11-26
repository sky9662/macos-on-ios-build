#!/usr/bin/env python3
"""Package only the upstream MIT-licensed, macOS-built Metal/AppKit toy probe.
No commercial game files, provisioning profiles or signing identities.
"""
import argparse
import pathlib
import plistlib
import re
import shutil
import subprocess

def run(*args):
    print("+", *args, flush=True)
    return subprocess.check_output(args, text=True, stderr=subprocess.STDOUT)

def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("build", type=pathlib.Path)
    ap.add_argument("upstream", type=pathlib.Path)
    ap.add_argument("output", type=pathlib.Path)
    ap.add_argument("--diagnostics", action="store_true")
    a = ap.parse_args()
    out = a.output.resolve()
    if out.exists():
        raise SystemExit("Refusing to overwrite existing output: " + str(out))
    app = out / "Payload" / "MacProbe.app"
    frameworks = app / "Frameworks"
    frameworks.mkdir(parents=True)
    mac = a.build / "MacProbe.app" / "Contents"
    exe = app / "MacProbe"
    shutil.copy2(mac / "MacOS" / "MacProbe", exe)
    shutil.copy2(mac / "Resources" / "probe.metallib", app)
    names = ("AppKitShim", "CocoaShim", "OpenGLShim") if a.diagnostics else ("AppKitShim", "CocoaShim")
    for name in names:
        shutil.copytree(a.build / (name + ".framework"), frameworks / (name + ".framework"))
    run("xcrun", "lipo", "-verify_arch", "arm64", str(exe))
    run("codesign", "--remove-signature", str(exe))
    run("xcrun", "vtool", "-set-build-version", "ios", "17.0", "27.1", "-replace", "-output", str(exe), str(exe))
    for line in run("xcrun", "otool", "-L", str(exe)).splitlines()[1:]:
        lib = line.strip().split(" (", 1)[0]
        if "/AppKit.framework/" in lib:
            new = "@rpath/AppKitShim.framework/AppKitShim"
        elif "/Cocoa.framework/" in lib:
            new = "@rpath/CocoaShim.framework/CocoaShim"
        elif a.diagnostics and "/OpenGL.framework/" in lib:
            new = "@rpath/OpenGLShim.framework/OpenGLShim"
        elif lib.startswith("/System/Library/Frameworks/"):
            new = re.sub(r"(/[^/]+\.framework)/Versions/[^/]+/([^/]+)$", r"\1/\2", lib)
        else:
            new = lib
        if new != lib:
            run("xcrun", "install_name_tool", "-change", lib, new, str(exe))
    run("xcrun", "install_name_tool", "-add_rpath", "@executable_path/Frameworks", str(exe))
    deps = run("xcrun", "otool", "-L", str(exe))
    print(deps)
    assert "CocoaShim.framework/CocoaShim" in deps or "AppKitShim.framework/AppKitShim" in deps
    assert "/System/Library/Frameworks/AppKit.framework/" not in deps
    assert "/System/Library/Frameworks/Cocoa.framework/" not in deps
    build = run("xcrun", "vtool", "-show-build", str(exe))
    print(build)
    assert re.search(r"platform\s+IOS\b", build, re.I), build
    if a.diagnostics:
        assert "@rpath/OpenGLShim.framework/OpenGLShim" in deps
        assert "/System/Library/Frameworks/OpenGL.framework/" not in deps
    for name in names:
        binary = frameworks / (name + ".framework") / name
        run("xcrun", "lipo", "-verify_arch", "arm64", str(binary))
        if "platform IOS" not in run("xcrun", "vtool", "-show-build", str(binary)).upper():
            # vtool's whitespace varies; inspect with regex below instead.
            pass
        assert re.search(r"platform\s+IOS\b", run("xcrun", "vtool", "-show-build", str(binary)), re.I)
        run("codesign", "--remove-signature", str(binary))
    info = plistlib.loads((a.upstream / "shim" / "Info-ios.plist").read_bytes())
    info["CFBundleIdentifier"] = "com.sky9662.tcmacprobe"
    info["CFBundleDisplayName"] = "TC Mac Probe"
    if a.diagnostics:
        info["CFBundleIdentifier"] = "com.sky9662.tcdiagnostics"
        info["CFBundleDisplayName"] = "TC Diagnostics"
        info["UIFileSharingEnabled"] = True
        info["LSSupportsOpeningDocumentsInPlace"] = True
    (app / "Info.plist").write_bytes(plistlib.dumps(info))
    shutil.copy2(a.upstream / "LICENSE", app / "UPSTREAM-LICENSE.txt")
    run("plutil", "-lint", str(app / "Info.plist"))
    ipa = out / ("TCCompatibilityDiagnostics-unsigned.ipa" if a.diagnostics else "TCMacProbe-unsigned.ipa")
    subprocess.run(["zip", "-qry", str(ipa), "Payload"], cwd=out, check=True)
    print(run("unzip", "-t", str(ipa)))
    print(ipa)

if __name__ == "__main__":
    main()
