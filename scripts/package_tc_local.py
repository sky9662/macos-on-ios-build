#!/usr/bin/env python3
"""Local-only unsigned Turing Complete IPA packer; blocks unresolved imports.
The user supplies an owned Mac game and a separately built source-only runtime kit.
No game data leaves this machine. Does not sign or bypass Steam checks.
"""
import argparse, json, pathlib, plistlib, shutil, tempfile, zipfile, stat
from tc_windows import NAMES, macapp, report, resolve_deps, convert, inspect

def packaged_path(path):
    if path.startswith("@rpath/"):
        return "@executable_path/Frameworks/"+path[len("@rpath/"):]
    if path.startswith("@loader_path/"):
        return "@executable_path/Frameworks/"+path[len("@loader_path/"):]
    return path

def safe_copy(src,dst):
    if not src.is_dir():raise ValueError(f"missing directory: {src}")
    for p in src.rglob("*"):
        if p.is_symlink():raise ValueError(f"symlink not supported: {p}")
    shutil.copytree(src,dst,ignore=shutil.ignore_patterns("_CodeSignature",".DS_Store","embedded.mobileprovision"))

def copy_game_resources(app,bundle):
    # The supplied Mac depot has these trees both outside the .app and inside
    # Contents/Resources. Use the canonical app copy once, in the iOS resource root.
    source=app/"Contents"/"Resources"
    for name in ("asset","campaign","translations"):
        if not (source/name).is_dir() or not any((source/name).rglob("*")):
            raise ValueError("missing game resource tree: "+name)
    # Validate the entire source and destination before copying anything.
    # Case-fold on every host so Windows/macOS/Linux reject the same collisions.
    children=sorted(source.iterdir(),key=lambda child:child.name.casefold())
    reserved={"frameworks","info.plist","turing complete","upstream-license.txt","_codesignature","embedded.mobileprovision"}
    seen=set()
    for child in children:
        key=child.name.casefold()
        if key in reserved:raise ValueError("resource collides with app metadata: "+child.name)
        if key in seen:raise ValueError("case-insensitive resource collision: "+child.name)
        seen.add(key)
        if child.is_symlink():raise ValueError("resource symlink: "+str(child))
        if not (child.is_dir() or child.is_file()):raise ValueError("unsupported resource: "+str(child))
        if child.is_dir():
            for item in child.rglob("*"):
                if item.is_symlink():raise ValueError("resource symlink: "+str(item))
                if not (item.is_dir() or item.is_file()):raise ValueError("unsupported resource: "+str(item))
    existing={child.name.casefold() for child in bundle.iterdir()}
    conflicts=seen & existing
    if conflicts:raise ValueError("resource destination already exists: "+", ".join(sorted(conflicts)))
    for child in children:
        if child.is_dir():safe_copy(child,bundle/child.name)
        else:shutil.copy2(child,bundle/child.name)

def validate_frameworks(root):
    for name in ("AppKitShim","CocoaShim","OpenGLShim","HIToolboxShim"):
        fw=root/(name+".framework")
        info=plistlib.loads((fw/"Info.plist").read_bytes())
        if info.get("CFBundleExecutable")!=name:
            raise ValueError("invalid framework executable: "+name)
        if inspect((fw/name).read_bytes())["platforms"]!=[2]:
            raise ValueError("non-iOS framework: "+name)
        if name=="OpenGLShim" and info.get("CFBundleIdentifier")!="com.apple.opengl":
            raise ValueError("GLFW bundle lookup identifier missing")
        if name=="HIToolboxShim" and info.get("CFBundleIdentifier")!="com.apple.HIToolbox":
            raise ValueError("GLFW keyboard bundle identifier missing")

def validate_local_paths(game,kit,out,audit):
    # Never overwrite source inputs or a prior audit, even on a failed preflight.
    game,kit,out,audit=(p.resolve() for p in (game,kit,out,audit))
    for target in (out,audit):
        if target.exists():raise ValueError("refusing to overwrite existing output: "+str(target))
        if not target.parent.is_dir():raise ValueError("missing output parent: "+str(target.parent))
        if any(target==root or root in target.parents for root in (game,kit)):
            raise ValueError("output must be outside input trees")
    if out==audit:raise ValueError("IPA and report paths must differ")

def package(game,kit,out,audit):
    validate_local_paths(game,kit,out,audit)
    if out.exists():raise ValueError("refusing to overwrite output")
    app,mac_info=macapp(game)
    data=report(game)
    cat=json.loads((kit/"ios-sdk-exports.json").read_text(encoding="utf-8"))
    mapping,missing=resolve_deps(data,cat)
    data["unresolved"]=missing
    data["mapping"]=mapping
    with audit.open("x",encoding="utf-8") as f:json.dump(data,f,indent=2)
    if missing:raise ValueError(f"{len(missing)} unresolved imports/dependencies; see {audit}. No IPA produced.")
    mapping={k:packaged_path(v) for k,v in mapping.items()}
    with tempfile.TemporaryDirectory(dir=out.parent) as td:
        root=pathlib.Path(td);bundle=root/"Payload"/"TuringComplete.app"
        bundle.mkdir(parents=True);frameworks=bundle/"Frameworks"
        safe_copy(kit/"Frameworks",frameworks)
        validate_frameworks(frameworks)
        shutil.copy2(kit/"UPSTREAM-LICENSE.txt",bundle/"UPSTREAM-LICENSE.txt")
        if (kit/"ThirdParty").is_dir():safe_copy(kit/"ThirdParty",bundle/"ThirdParty")
        copy_game_resources(app,bundle)
        # No second copy of executable code; resource path compatibility still requires device testing.
        for n in NAMES:
            raw=(app/"Contents/MacOS"/n).read_bytes()
            converted=convert(raw,mapping,install_id="@rpath/"+n if n.endswith(".dylib") else None,rpath="@executable_path/Frameworks" if n=="Turing Complete" else None)
            dest=(frameworks if n.endswith(".dylib") else bundle)/n
            dest.write_bytes(converted)
            if inspect(converted)["platforms"]!=[2]:raise ValueError("unexpected converted platform")
        info=plistlib.loads((kit/"Info-ios.plist").read_bytes())
        info.update({"CFBundleExecutable":"Turing Complete","CFBundleIdentifier":"com.sky9662.turingcomplete","CFBundleName":"Turing Complete","CFBundleDisplayName":"Turing Complete","CFBundleVersion":"1","CFBundleShortVersionString":"0.1","UIFileSharingEnabled":True,"LSSupportsOpeningDocumentsInPlace":True})
        (bundle/"Info.plist").write_bytes(plistlib.dumps(info))
        archive=root/"output.ipa"
        executable_paths={bundle/"Turing Complete",*(frameworks/n for n in NAMES if n.endswith(".dylib"))}
        for fw in frameworks.glob("*.framework"):
            executable_paths.add(fw/fw.stem)
        with zipfile.ZipFile(archive,"w",compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
            for f in sorted(bundle.rglob("*")):
                if not f.is_file():continue
                zi=zipfile.ZipInfo(f.relative_to(root).as_posix());zi.create_system=3
                zi.external_attr=(stat.S_IFREG|(0o755 if f in executable_paths else 0o644))<<16
                zi.compress_type=zipfile.ZIP_DEFLATED
                with f.open("rb") as inp,z.open(zi,"w",force_zip64=True) as dst:shutil.copyfileobj(inp,dst)
        with zipfile.ZipFile(archive) as z:
            if z.testzip():raise ValueError("corrupt IPA archive")
        shutil.move(str(archive),str(out))
    print("Unsigned local IPA created. Installation and actual game launch are unverified:",out)

if __name__=="__main__":
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("game",type=pathlib.Path);p.add_argument("--kit",required=True,type=pathlib.Path)
    p.add_argument("--output",required=True,type=pathlib.Path);p.add_argument("--report",required=True,type=pathlib.Path)
    a=p.parse_args()
    try:package(a.game,a.kit,a.output,a.report)
    except (ValueError,OSError) as e:raise SystemExit(str(e))
