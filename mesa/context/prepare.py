#!/usr/bin/env python3
"""Reuse the pinned Mac probe, replacing only its graphics adapter."""
import pathlib, subprocess, sys
repo=pathlib.Path(__file__).resolve().parents[2]
up=pathlib.Path(sys.argv[1]).resolve()
subprocess.run([sys.executable,str(repo/"scripts/patch_upstream_probe.py"),str(up/"probe/build.sh")],check=True)
subprocess.run([sys.executable,str(repo/"scripts/prepare_diagnostics.py"),str(up)],check=True)
def replace(path,old,new):
    s=path.read_text()
    if s.count(old)!=1: raise SystemExit(f"Unexpected anchor in {path}")
    path.write_text(s.replace(old,new,1))
replace(up/"shim/overrides/AppKit.m",(repo/"diagnostics/appkit.m").read_text(),(repo/"mesa/context/appkit-context.m").read_text())
(up/"probe/macapp/tc_diagnostics.m").write_text((repo/"mesa/context/mac-diagnostics.m").read_text())
replace(up/"probe/build.sh","-framework GameController -framework OpenGLES -framework UniformTypeIdentifiers ../shim/overrides/AppKit.m",
        '-framework GameController -framework Metal -framework UniformTypeIdentifiers -F"$T" -framework OpenGLShim ../shim/overrides/AppKit.m')

# Register the embedded OpenGL bundle before GLFW's initialization lookup.
# Only modify the pinned disposable AppKit shim.
replace(up/"shim/overrides/AppKit.m",
        "@implementation NSApplication\nSHIM_RESOLVE\n+ (instancetype)sharedApplication {\n",
        "static void TCRegisterMesaGLBundle(void);\n@implementation NSApplication\nSHIM_RESOLVE\n+ (instancetype)sharedApplication {\n    TCRegisterMesaGLBundle();\n")
