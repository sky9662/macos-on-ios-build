#!/usr/bin/env python3
"""Produce portable export catalog on the existing macOS CI runner (no game inputs)."""
import json, pathlib, sys, subprocess
upstream,build,out=map(pathlib.Path,sys.argv[1:])
sys.path.insert(0,str(upstream/"tools"))
from gap import IOSIndex
idx=IOSIndex()
libraries={}
for name in sorted(idx.names):
    if "/PrivateFrameworks/" in name or "/SubFrameworks/" in name:continue
    libraries[name]=sorted(set().union(*(idx.direct.get(n,set()) for n in idx.tree(name))))
mapping={}
for mac,shim in [("AppKit","AppKitShim"),("Cocoa","CocoaShim"),("OpenGL","OpenGLShim")]:
    fw=build/(shim+".framework")/shim
    # nm -gUj: actual locally defined external symbols, not guesses.
    exports=set(subprocess.check_output(["xcrun","nm","-gUj",str(fw)],text=True).splitlines())
    dest="@rpath/"+shim+".framework/"+shim
    # The proven shim reexports OpenGLES or AppKit; Cocoa also uses Foundation.
    if mac=="OpenGL":
        mesa=build/"MesaCore.framework"/"MesaCore"
        if mesa.is_file():
            exports.update(subprocess.check_output(["xcrun","nm","-gUj",str(mesa)],text=True).splitlines())
        else:
            exports.update(libraries.get("/System/Library/Frameworks/OpenGLES.framework/OpenGLES",[]))
    if mac=="Cocoa":
        exports.update(libraries.get("@rpath/AppKitShim.framework/AppKitShim",[]))
    libraries[dest]=sorted(exports)
    for version in ("A","B","C"):
        mapping[f"/System/Library/Frameworks/{mac}.framework/Versions/{version}/{mac}"]=dest
    mapping[f"/System/Library/Frameworks/{mac}.framework/{mac}"]=dest
out.write_text(json.dumps({"libraries":libraries,"mapping":mapping},separators=(",",":")),encoding="utf-8")
