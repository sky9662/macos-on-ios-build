#!/usr/bin/env python3
"""Windows-compatible, read-only-by-default Mach-O audit and unsigned local staging.
No external libraries, network access, game execution, or signing.
"""
import argparse
import hashlib
import json
import pathlib
import plistlib
import re
import struct
import sys
import tempfile
import zipfile
import shutil

ARM64=0x0100000c
LOADS={0xc,0x80000018,0x8000001f,0x20,0x80000023}
ID=0xd
BUILD=0x32
SEG=0x19
SIG=0x1d
RPATH=0x8000001c
def u32(b,p): return struct.unpack_from("<I",b,p)[0]
def u64(b,p): return struct.unpack_from("<Q",b,p)[0]
def set32(b,p,n): struct.pack_into("<I",b,p,n)
def set64(b,p,n): struct.pack_into("<Q",b,p,n)
def align(n,a=8): return (n+a-1)//a*a
def string(b,p,end):
    if p>=end: raise ValueError("invalid Mach-O string offset")
    z=b.find(b"\0",p,end)
    if z<0: raise ValueError("unterminated Mach-O string")
    return b[p:z].decode("utf-8")
def thin(raw):
    if raw[:4]==b"\xcf\xfa\xed\xfe":
        data=raw
    elif raw[:4] in (b"\xca\xfe\xba\xbe",b"\xca\xfe\xba\xbf"):
        wide=raw[:4]==b"\xca\xfe\xba\xbf"
        count=struct.unpack_from(">I",raw,4)[0]
        if count>64: raise ValueError("invalid fat count")
        candidates=[]
        for i in range(count):
            off=8+i*(32 if wide else 20)
            cpu,sub,pos,size,*_=struct.unpack_from(">IIQQII" if wide else ">IIIII",raw,off)
            if cpu==ARM64 and sub&0xff==0:
                if pos+size>len(raw): raise ValueError("truncated ARM slice")
                candidates.append(raw[pos:pos+size])
        if len(candidates)!=1: raise ValueError("expected one ordinary ARM64 slice")
        data=candidates[0]
    else: raise ValueError("unsupported Mach-O magic")
    if len(data)<32 or data[:4]!=b"\xcf\xfa\xed\xfe" or u32(data,4)!=ARM64 or u32(data,8)&0xff!=0:
        raise ValueError("expected ARM64 little-endian Mach-O")
    return bytearray(data)
def commands(b):
    count,size=u32(b,16),u32(b,20)
    end=32+size; p=32; out=[]
    if end>len(b) or count>4096: raise ValueError("invalid header")
    for i in range(count):
        if p+8>end: raise ValueError("truncated command")
        c,z=struct.unpack_from("<II",b,p)
        if z<8 or z%8 or p+z>end: raise ValueError("invalid command size")
        out.append((c,bytearray(b[p:p+z])))
        p+=z
    if p!=end: raise ValueError("command total mismatch")
    return out
def dep_name(cmd): return string(cmd,u32(cmd,8),len(cmd))
def sections(cmd):
    if len(cmd)<72: raise ValueError("short segment")
    n=u32(cmd,64)
    if 72+n*80>len(cmd): raise ValueError("short section table")
    for i in range(n):
        pos=72+i*80; offset=u32(cmd,pos+48)
        if offset: yield offset
def inspect(raw):
    b=thin(raw); cs=commands(b)
    libs=[dep_name(x) for c,x in cs if c in LOADS]
    sym=next((x for c,x in cs if c==2),None)
    imports=[]; exports=[]
    if sym:
        off,n,st,sz=struct.unpack_from("<IIII",sym,8)
        if off+16*n>len(b) or st+sz>len(b): raise ValueError("truncated symbol table")
        for i in range(n):
            si,ty,sect,desc,val=struct.unpack_from("<IBBHQ",b,off+i*16)
            if ty&0xe0 or not ty&1 or si>=sz: continue
            name=string(b,st+si,st+sz)
            if ty&0xe==0 and val==0:
                ordinal=desc>>8
                imports.append({"name":name,"library":libs[ordinal-1] if 0<ordinal<=len(libs) else None,"ordinal":ordinal,"weak":bool(desc&0x40)})
            elif ty&0xe in (2,14):
                exports.append(name)
    return {"sha256":hashlib.sha256(raw).hexdigest(),"size":len(raw),
            "dependencies":libs,"rpaths":[dep_name(x) for c,x in cs if c==RPATH],
            "flat_namespace":not bool(u32(b,24)&0x80),
            "platforms":[u32(x,8) for c,x in cs if c==BUILD],
            "imports":imports,"exports":sorted(set(exports))}
def rename(cmd,name,head):
    data=name.encode("utf-8")+b"\0"; start=u32(cmd,8)
    if start<head or start>len(cmd): raise ValueError("invalid string offset")
    out=bytearray(cmd[:start])+data
    out.extend(b"\0"*(align(len(out))-len(out)))
    set32(out,4,len(out))
    return out
def convert(raw,mapping,install_id=None,rpath=None):
    b=thin(raw); cs=commands(b); oldend=32+u32(b,20)
    if any(c in (0x21,0x2c) and u32(x,16)!=0 for c,x in cs):
        raise ValueError("encrypted executable not supported")
    offsets=[v for c,x in cs if c==SEG for v in sections(x)]
    if not offsets: raise ValueError("cannot establish header boundary")
    boundary=min(offsets)
    if boundary<oldend or boundary>len(b): raise ValueError("invalid header boundary")
    signatures=[x for c,x in cs if c==SIG]
    if len(signatures)>1: raise ValueError("multiple code signatures")
    if signatures:
        off,size=struct.unpack_from("<II",signatures[0],8)
        if off+size!=len(b): raise ValueError("signature is not trailing")
        linkedit=[x for c,x in cs if c==SEG and bytes(x[8:24]).rstrip(b"\0")==b"__LINKEDIT"]
        if len(linkedit)!=1: raise ValueError("missing __LINKEDIT")
        x=linkedit[0]; fileoff=u64(x,40); filesize=u64(x,48)
        if fileoff+filesize!=len(b) or off<fileoff: raise ValueError("unexpected linkedit bounds")
        set64(x,48,off-fileoff)
        # Keep VM size; only the trailing file signature is removed.
        del b[off:]
    new=[]; platform=0
    for c,x in cs:
        if c==SIG: continue
        if c==BUILD:
            if u32(x,8)!=1: raise ValueError("input must target macOS")
            set32(x,8,2);set32(x,12,0x110000);set32(x,16,0x1b0100);platform+=1
        if c in LOADS:
            old=dep_name(x)
            if old in mapping:x=rename(x,mapping[old],24)
        if c==ID and install_id:x=rename(x,install_id,24)
        if c==RPATH and rpath:x=rename(x,rpath,12)
        new.append(x)
    if platform!=1: raise ValueError("expected one LC_BUILD_VERSION")
    payload=b"".join(new)
    end=32+len(payload)
    if end>boundary: raise ValueError(f"insufficient Mach-O header padding: need {end}, have {boundary}")
    if end>oldend and any(b[oldend:end]): raise ValueError("header growth would overwrite nonzero data")
    b[32:max(oldend,end)]=payload+b"\0"*(max(oldend,end)-end)
    set32(b,16,len(new));set32(b,20,len(payload))
    if inspect(b)["platforms"]!=[2]: raise ValueError("retag verification failed")
    return bytes(b)
def macapp(path):
    path=path.resolve()
    if path.suffix.lower()!=".app":path=path/"Turing Complete.app"
    info=plistlib.loads((path/"Contents/Info.plist").read_bytes())
    if info.get("CFBundleExecutable")!="Turing Complete":raise ValueError("not expected Turing Complete Mac bundle")
    return path,info
NAMES=("Turing Complete","compile.dylib","game_engine.dylib","libsteam_api.dylib")
def report(path):
    app,info=macapp(path)
    root=app/"Contents/MacOS"
    data={name:inspect((root/name).read_bytes()) for name in NAMES}
    return {"bundle":info.get("CFBundleIdentifier"),"binaries":data}
def resolve_deps(report,catalog):
    """Fail closed on absent dependencies/strong symbols; flat lookup is an estimate, not a runtime proof."""
    unresolved=[]; mapping={}
    available=catalog["libraries"]
    exports={k:set(v["exports"]) for k,v in report["binaries"].items()}
    provided=set().union(*exports.values(),*(set(v) for v in available.values()))
    for name,entry in report["binaries"].items():
        deps={}
        for dep in entry["dependencies"]:
            lib=dep.rsplit("/",1)[-1]
            if dep.startswith(("@rpath/","@loader_path/")) and lib in exports:
                new="@loader_path/"+lib
                symbols=exports[lib]
            else:
                new=catalog["mapping"].get(dep,dep)
                if new not in available:
                    new=re.sub(r"(/[^/]+\.framework)/Versions/[^/]+/([^/]+)$",r"\1/\2",new)
                symbols=set(available.get(new,[]))
                if new not in available:unresolved.append(f"{name}: library {dep} -> {new}")
            deps[dep]=symbols
            mapping[dep]=new
        visible=set().union(*exports.values(),*deps.values())
        for imp in entry["imports"]:
            if imp["weak"]:continue
            if imp["library"] in deps: ok=imp["name"] in deps[imp["library"]]
            elif imp["ordinal"]==0:ok=imp["name"] in visible
            elif imp["ordinal"] in (254,255):ok=imp["name"] in provided
            else:ok=False
            if not ok:unresolved.append(f"{name}: {imp['library'] or 'flat'} {imp['name']}")
    return mapping,sorted(set(unresolved))
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("game",type=pathlib.Path);p.add_argument("--catalog",type=pathlib.Path)
    p.add_argument("--report",type=pathlib.Path,required=True)
    p.add_argument("--stage",type=pathlib.Path,help="local staging directory; refuses unresolved imports")
    a=p.parse_args()
    data=report(a.game)
    if a.catalog:
        catalog=json.loads(a.catalog.read_text(encoding="utf-8"))
        mapping,unresolved=resolve_deps(data,catalog)
        data["mapping"]=mapping;data["unresolved"]=unresolved
    else:unresolved=["SDK/runtime export catalog not supplied"]
    a.report.write_text(json.dumps(data,indent=2),encoding="utf-8")
    print("Audit written:",a.report,"unresolved:",len(unresolved))
    if a.stage:
        if unresolved:raise SystemExit("Staging refused: unresolved dependencies; see report")
        app,_=macapp(a.game)
        if a.stage.exists():raise SystemExit("Staging refuses existing directory")
        # Prepare unsigned binaries only; final bundle/resources/signing are a separate gate.
        with tempfile.TemporaryDirectory(dir=a.stage.parent) as tmp:
            root=pathlib.Path(tmp)/"converted";root.mkdir()
            for name in NAMES:
                raw=(app/"Contents/MacOS"/name).read_bytes()
                out=convert(raw,mapping,install_id="@loader_path/"+name if name.endswith(".dylib") else None)
                (root/name).write_bytes(out)
            shutil.move(str(root),str(a.stage))
        print("Converted unsigned binaries staged; not an IPA")
if __name__=="__main__":main()
