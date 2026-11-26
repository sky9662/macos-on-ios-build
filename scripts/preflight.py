#!/usr/bin/env python3
"""Read-only ARM64 Mach-O inspection."""
import argparse, hashlib, json, pathlib, re, shutil, subprocess, sys
def inspect(root):
    tool=shutil.which('llvm-objdump')
    if not tool and sys.platform=='darwin':
        tool=subprocess.check_output(['xcrun','--find','llvm-objdump'],text=True).strip()
    if not tool: raise RuntimeError('llvm-objdump required')
    result={}
    for name in ['Turing Complete','compile.dylib','game_engine.dylib','libsteam_api.dylib']:
        p=root/name
        data=p.read_bytes()
        def run(flag):
            return subprocess.check_output([tool,'--macho','--arch=arm64',flag,str(p)],text=True,stderr=subprocess.STDOUT)
        deps=run('--dylibs-used')
        syms=run('--syms')
        markers=sorted(set(re.findall(r'(?m)\*UND\*\s+(_\S+)',syms)))
        result[name]={'sha256':hashlib.sha256(data).hexdigest(),'size':len(data),'dependencies':deps.splitlines()[1:],'jit_imports':[s for s in markers if re.search(r'jit|mmap|mprotect|icache',s,re.I)],'gl_context_imports':[s for s in markers if re.search(r'NSOpenGL|CGL',s)],'glsl_versions':sorted(set(x.decode() for x in re.findall(rb'#version [0-9]+',data)))}
    return result
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('binary_directory',type=pathlib.Path)
    parser.add_argument('--output',type=pathlib.Path)
    a=parser.parse_args()
    data=json.dumps(inspect(a.binary_directory),indent=2)+'\n'
    if a.output: a.output.write_text(data,encoding='utf-8')
    else: print(data,end='')
