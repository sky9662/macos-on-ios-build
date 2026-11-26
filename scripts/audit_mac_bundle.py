#!/usr/bin/env python3
"""Read-only cross-version Mac bundle scan. Never executes, patches or packages game code."""
import argparse
import json
import os
import pathlib
import plistlib
import struct

from tc_windows import inspect, thin, commands

MAGICS = {b"\xcf\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xce\xfa\xed\xfe",
          b"\xfe\xed\xfa\xce", b"\xca\xfe\xba\xbe", b"\xca\xfe\xba\xbf",
          b"\xbe\xba\xfe\xca", b"\xbf\xba\xfe\xca"}
PROTECTION = {"_pthread_jit_write_protect_np", "_pthread_jit_write_with_callback_np",
              "_pthread_jit_write_protect_supported_np"}
SIGNALS = PROTECTION | {"_sys_icache_invalidate", "_sys_dcache_flush"}
MEMORY = {"_mmap", "_mprotect", "_mach_vm_protect"}
DYNAMIC = {"_dlopen", "_dlsym", "_CFBundleGetFunctionPointerForName"}
MAX_BINARY = 512 * 1024 * 1024

def scan_binary(path, relative):
    entry = {"path": relative}
    try:
        if path.stat().st_size > MAX_BINARY:
            raise ValueError("binary exceeds scan size limit")
        raw = path.read_bytes()
        info = inspect(raw)
        cs = commands(thin(raw))
        names = {i["name"] for i in info["imports"]}
        # A missing symbol table or chained fixups make a negative result inconclusive.
        has_table = any(cmd == 2 and len(data) >= 24 and struct.unpack_from("<I", data, 12)[0] > 0
                        for cmd, data in cs)
        entry.update({"status": "arm64-inspected", "sha256": info["sha256"],
                      "platforms": info["platforms"], "dependencies": info["dependencies"],
                      "symbol_table_present": has_table,
                      "chained_fixups_present": any(cmd == 0x80000034 for cmd, _ in cs),
                      "jit_imports": sorted(names & SIGNALS),
                      "memory_imports": sorted(names & MEMORY),
                      "dynamic_lookup_imports": sorted(names & DYNAMIC),
                      "macos_only_jit_import": "_pthread_jit_write_protect_np" in names})
    except (ValueError, OSError, struct.error, UnicodeError) as exc:
        entry.update({"status": "uninspected", "reason": str(exc)})
    return entry

def scan_bundle(bundle):
    bundle = pathlib.Path(bundle)
    if bundle.is_symlink() or not bundle.is_dir():
        raise ValueError("expected local .app directory, not symlink")
    info_path = bundle / "Contents" / "Info.plist"
    if info_path.is_symlink() or not info_path.is_file():
        raise ValueError("missing regular Contents/Info.plist")
    info = plistlib.loads(info_path.read_bytes())
    executable = info.get("CFBundleExecutable")
    if not isinstance(executable, str) or not executable or pathlib.PurePosixPath(executable).name != executable or "/" in executable or "\\" in executable or executable in (".", ".."):
        raise ValueError("invalid CFBundleExecutable")
    main = "Contents/MacOS/" + executable
    entries = []
    skipped = []
    def walk_error(exc):
        skipped.append({"path": "bundle traversal", "reason": str(exc)})
    for root, dirs, files in os.walk(bundle, followlinks=False, onerror=walk_error):
        root = pathlib.Path(root)
        for name in sorted(dirs):
            p = root / name
            if p.is_symlink():
                skipped.append({"path": p.relative_to(bundle).as_posix(), "reason": "directory symlink not followed"})
                dirs.remove(name)
        for name in sorted(files):
            p = root / name
            relative = p.relative_to(bundle).as_posix()
            if p.is_symlink() or not p.is_file():
                skipped.append({"path": relative, "reason": "non-regular file or symlink"})
                continue
            try:
                with p.open("rb") as f:
                    magic = f.read(4)
            except OSError as exc:
                skipped.append({"path": relative, "reason": str(exc)})
                continue
            if magic in MAGICS:
                entries.append(scan_binary(p, relative))
    entries.sort(key=lambda e: e["path"])
    primary = next((e for e in entries if e["path"] == main), None)
    if not primary or primary["status"] != "arm64-inspected":
        status = "main-arm64-unverified"
    elif any(e.get("macos_only_jit_import") for e in entries):
        status = "macos-only-jit-import-observed"
    elif any(e.get("jit_imports") for e in entries):
        status = "jit-signals-observed"
    else:
        status = "no-listed-jit-symbol-observed"
    return {"bundle_identifier": info.get("CFBundleIdentifier"),
            "version": info.get("CFBundleShortVersionString"), "main": main,
            "status": status, "binaries": entries, "skipped": skipped,
            "limits": "Static nlist inspection only; absence of imports does not rule out JIT, dynamic lookups or stripped/chained bindings. Symlinks are not followed. No device or runtime validation.",
            "game_launch_authorized": False, "runtime_verified": False}

def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("bundle", type=pathlib.Path)
    p.add_argument("--output", type=pathlib.Path, required=True)
    args = p.parse_args()
    try:
        result = scan_bundle(args.bundle)
        # Prevent accidental mutation inside the supplied app.
        if args.output.resolve().is_relative_to(args.bundle.resolve()):
            raise ValueError("output must be outside input bundle")
        with args.output.open("x", encoding="utf-8") as f:
            json.dump(result, f, indent=2)
            f.write("\n")
    except (ValueError, OSError, plistlib.InvalidFileException) as exc:
        p.exit(1, str(exc) + "\n")
    print(result["status"], "- runtime unverified; report:", args.output)

if __name__ == "__main__":
    main()
