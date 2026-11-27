import struct
import unittest
from tc_windows import *
def sample():
    seg=bytearray(152);struct.pack_into("<II",seg,0,SEG,len(seg));seg[8:14]=b"__TEXT"
    struct.pack_into("<I",seg,64,1);struct.pack_into("<I",seg,120,1024)
    link=bytearray(72);struct.pack_into("<II",link,0,SEG,len(link));link[8:18]=b"__LINKEDIT";struct.pack_into("<QQ",link,40,1280,32)
    build=struct.pack("<6I",BUILD,24,1,0x1a0000,0x1a0500,0)
    dep=bytearray(80);struct.pack_into("<6I",dep,0,0xc,80,24,0,0,0);dep[24:28]=b"old\0"
    sig=struct.pack("<4I",SIG,16,1296,16)
    cmds=bytes(seg+link+build+dep+sig)
    hdr=struct.pack("<8I",0xfeedfacf,ARM64,0,2,5,len(cmds),0x80,0)
    b=bytearray(hdr+cmds);b.extend(b"\0"*(1312-len(b)));b[1024:1028]=b"CODE"
    return bytes(b)
class Test(unittest.TestCase):
    def test_convert(self):
        raw=sample();result=convert(raw,{"old":"@rpath/new.framework/new"})
        self.assertEqual(inspect(result)["platforms"],[2])
        self.assertEqual(inspect(result)["dependencies"],["@rpath/new.framework/new"])
        self.assertEqual(result[1024:1028],b"CODE")
        self.assertEqual(len(result),1296)
        self.assertFalse(any(c==SIG for c,_ in commands(result)))
    def test_guard(self):
        with self.assertRaises(ValueError):convert(sample(),{"old":"a"*2048})
    def test_original_unchanged(self):
        raw=sample();before=hashlib.sha256(raw).digest();convert(raw,{})
        self.assertEqual(hashlib.sha256(raw).digest(),before)
    def test_versioned_sdk_path(self):
        path="/System/Library/Frameworks/IOKit.framework/Versions/A/IOKit"
        sample={"binaries":{"test":{"exports":[],"dependencies":[path],"imports":[{"name":"_IOObjectRelease","library":path,"ordinal":1,"weak":False}]}}}
        mapping,missing=resolve_deps(sample,{"mapping":{},"libraries":{path:["_IOObjectRelease"]}})
        self.assertEqual(mapping[path],path)
        self.assertEqual(missing,[])
    def test_chained_imports(self):
        for fmt,stride in ((1,4),(2,8),(3,16)):
            names=b"_example\0_weak\0"
            entries=bytearray(2*stride)
            if fmt==3:
                struct.pack_into("<Q",entries,0,1)
                struct.pack_into("<Q",entries,stride,0xfffe|0x10000|(9<<32))
            else:
                struct.pack_into("<I",entries,0,1)
                struct.pack_into("<I",entries,stride,0xfe|0x100|(9<<9))
            data=struct.pack("<7I",0,28,28,28+len(entries),2,fmt,0)+entries+names
            cmd=struct.pack("<4I",CHAINED_FIXUPS,16,0,len(data))
            result=chained_imports(data,[(CHAINED_FIXUPS,cmd)],["lib"])
            self.assertEqual(result[0]["name"],"_example")
            self.assertEqual(result[0]["library"],"lib")
            self.assertEqual(result[1]["name"],"_weak")
            self.assertEqual(result[1]["ordinal"],-2)
            self.assertTrue(result[1]["weak"])
            with self.assertRaises(ValueError):chained_imports(data[:-1],[(CHAINED_FIXUPS,cmd)],["lib"])
    def test_legacy_jit_gate(self):
        lib="/usr/lib/libSystem.B.dylib"
        binary={"exports":[],"dependencies":[lib],"imports":[{"name":"_pthread_jit_write_protect_np","library":lib,"ordinal":1,"weak":False}]}
        _,missing=resolve_deps({"binaries":{"test":binary}},{"mapping":{},"libraries":{lib:["_pthread_jit_write_protect_np"]}})
        self.assertEqual(missing,["test: "+lib+" _pthread_jit_write_protect_np"])
    def test_fat(self):
        s=sample();fat=struct.pack(">7I",0xcafebabe,1,ARM64,0,32,len(s),0)+b"\0"*4+s
        self.assertEqual(thin(fat),thin(s))
if __name__=="__main__":unittest.main()
