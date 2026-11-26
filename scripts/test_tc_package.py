"""Exercise the entire IPA packer with locally generated, non-commercial fixtures."""
import hashlib, json, pathlib, plistlib, shutil, subprocess, sys, tempfile, unittest, zipfile
from tc_windows import NAMES, convert, inspect
from test_tc_windows import sample
from package_tc_local import package, copy_game_resources

def resources(app):
    p=app/"Contents"/"Resources"
    for name in ("asset","campaign","translations"):
        (p/name).mkdir(parents=True)
        (p/name/"sample.txt").write_text(name,encoding="utf-8")
    (p/"icon.icns").write_bytes(b"fixture-icon")

class Test(unittest.TestCase):
    def test_resource_layout(self):
        with tempfile.TemporaryDirectory() as td:
            root=pathlib.Path(td);app=root/"Turing Complete.app";bundle=root/"ios";bundle.mkdir()
            resources(app);copy_game_resources(app,bundle)
            self.assertEqual((bundle/"asset/sample.txt").read_text(),"asset")
            self.assertTrue((bundle/"campaign/sample.txt").is_file())
            self.assertTrue((bundle/"translations/sample.txt").is_file())
            self.assertFalse((bundle/"Resources").exists())
            self.assertTrue((bundle/"icon.icns").is_file())
            # Existing files are never overwritten, even when source data changes.
            (app/"Contents/Resources/asset/sample.txt").write_text("changed",encoding="utf-8")
            with self.assertRaisesRegex(ValueError,"destination already exists"):copy_game_resources(app,bundle)
            self.assertEqual((bundle/"asset/sample.txt").read_text(),"asset")

    def test_metadata_collision_is_rejected_before_any_copy(self):
        with tempfile.TemporaryDirectory() as td:
            root=pathlib.Path(td);app=root/"Turing Complete.app";bundle=root/"ios";bundle.mkdir()
            resources(app)
            (app/"Contents/Resources/iNfO.pLiSt").write_text("collision")
            with self.assertRaisesRegex(ValueError,"collides with app metadata"):copy_game_resources(app,bundle)
            self.assertEqual(list(bundle.iterdir()),[])

    def test_case_insensitive_destination_collision(self):
        with tempfile.TemporaryDirectory() as td:
            root=pathlib.Path(td);app=root/"Turing Complete.app";bundle=root/"ios";bundle.mkdir()
            resources(app)
            (bundle/"ASSET").mkdir()
            (bundle/"ASSET/original.txt").write_text("keep")
            with self.assertRaisesRegex(ValueError,"destination already exists"):copy_game_resources(app,bundle)
            self.assertEqual((bundle/"ASSET/original.txt").read_text(),"keep")
            self.assertEqual(len(list(bundle.iterdir())),1)

def real(kit):
    # These four binaries are compiled from our own tiny source, not the game.
    with tempfile.TemporaryDirectory() as td:
        root=pathlib.Path(td);app=root/"Turing Complete.app";mac=app/"Contents/MacOS";mac.mkdir(parents=True)
        (app/"Contents/Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable":"Turing Complete","CFBundleIdentifier":"org.example.tc-fixture"}))
        resources(app)
        source=root/"fixture.c"
        for i,n in enumerate(NAMES[1:]):
            source.write_text("int fixture_%d(void){return %d;}\n"%(i,i+1))
            subprocess.run(["xcrun","--sdk","macosx","clang","-arch","arm64","-dynamiclib","-Wl,-headerpad_max_install_names","-install_name","@rpath/"+n,str(source),"-o",str(mac/n)],check=True)
        source.write_text("extern int fixture_0(void),fixture_1(void),fixture_2(void); int main(void){return fixture_0()+fixture_1()+fixture_2()==6?0:1;}\n")
        subprocess.run(["xcrun","--sdk","macosx","clang","-arch","arm64","-Wl,-headerpad_max_install_names","-Wl,-rpath,@executable_path",str(source),*[str(mac/n) for n in NAMES[1:]],"-o",str(mac/NAMES[0])],check=True)
        before={n:hashlib.sha256((mac/n).read_bytes()).hexdigest() for n in NAMES}
        out=root/"fixture.ipa";report=root/"audit.json"
        package(app,kit,out,report)
        assert not json.loads(report.read_text())["unresolved"]
        assert before=={n:hashlib.sha256((mac/n).read_bytes()).hexdigest() for n in NAMES}
        with zipfile.ZipFile(out) as z:
            prefix="Payload/TuringComplete.app/"
            names=set(z.namelist());assert z.testzip() is None
            assert prefix+"asset/sample.txt" in names and prefix+"translations/sample.txt" in names and prefix+"campaign/sample.txt" in names
            assert prefix+"Resources/asset/sample.txt" not in names
            for n in NAMES:
                path=prefix+("Frameworks/" if n.endswith(".dylib") else "")+n
                assert inspect(z.read(path))["platforms"]==[2]
                assert z.getinfo(path).external_attr>>16 & 0o111
            for n in NAMES[1:]:assert "@executable_path/Frameworks/"+n in inspect(z.read(prefix+NAMES[0]))["dependencies"]
            assert plistlib.loads(z.read(prefix+"Info.plist"))["CFBundleExecutable"]==NAMES[0]
        # Verify that an unresolved import blocks the real packaging path, even when all resources exist.
        broken=root/"bad-kit";shutil.copytree(kit,broken)
        (broken/"ios-sdk-exports.json").write_text('{"libraries":{},"mapping":{}}')
        blocked=root/"blocked.ipa"
        try:package(app,broken,blocked,root/"blocked.json")
        except ValueError as e:assert "unresolved" in str(e)
        else:raise AssertionError("unresolved import gate did not block packaging")
        assert not blocked.exists()
        print("End-to-end real ARM64 fixture IPA, resource layout, permissions, original hashes and fail-closed audit PASS")
if __name__=="__main__":
    if len(sys.argv)==2 and pathlib.Path(sys.argv[1]).is_dir():real(pathlib.Path(sys.argv[1]).resolve())
    else:unittest.main()
