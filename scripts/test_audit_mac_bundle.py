import pathlib
import plistlib
import struct
import tempfile
import unittest
from unittest.mock import patch
from audit_mac_bundle import scan_bundle, scan_binary
from test_tc_windows import sample

class TestBundleScan(unittest.TestCase):
    def fixture(self, root):
        bundle = root / "Fixture.app"
        folder = bundle / "Contents" / "MacOS"
        folder.mkdir(parents=True)
        (bundle / "Contents" / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable":"Fixture"}))
        (folder / "Fixture").write_bytes(sample())
        return bundle, folder

    def test_read_only_recursive_bundle(self):
        with tempfile.TemporaryDirectory() as td:
            app, folder = self.fixture(pathlib.Path(td))
            fw = app / "Contents" / "Frameworks"
            fw.mkdir()
            (fw / "backend.dylib").write_bytes(sample())
            (fw / "asset.dat").write_bytes(b"not a Mach-O")
            result = scan_bundle(app)
            self.assertEqual(len(result["binaries"]), 2)
            self.assertEqual(result["status"], "no-listed-jit-symbol-observed")
            self.assertFalse(result["runtime_verified"])
            self.assertFalse(result["game_launch_authorized"])
            self.assertEqual((folder / "Fixture").read_bytes(), sample())

    def test_x86_main_is_not_candidate(self):
        with tempfile.TemporaryDirectory() as td:
            app, folder = self.fixture(pathlib.Path(td))
            raw = bytearray(sample())
            struct.pack_into("<I", raw, 4, 0x01000007)
            (folder / "Fixture").write_bytes(raw)
            result = scan_bundle(app)
            self.assertEqual(result["status"], "main-arm64-unverified")
            self.assertEqual(result["binaries"][0]["status"], "uninspected")

    def test_import_signal(self):
        with tempfile.TemporaryDirectory() as td:
            app, folder = self.fixture(pathlib.Path(td))
            info = {"sha256": "fixture", "platforms":[1], "dependencies":[],
                    "imports":[{"name":"_pthread_jit_write_protect_np"}]}
            with patch("audit_mac_bundle.inspect", return_value=info):
                result = scan_bundle(app)
            self.assertEqual(result["status"], "macos-only-jit-import-observed")
            self.assertFalse(result["game_launch_authorized"])

    def test_invalid_executable(self):
        with tempfile.TemporaryDirectory() as td:
            app, folder = self.fixture(pathlib.Path(td))
            (app / "Contents" / "Info.plist").write_bytes(plistlib.dumps({"CFBundleExecutable":"../bad"}))
            with self.assertRaises(ValueError):
                scan_bundle(app)

    def test_truncated_binary(self):
        with tempfile.TemporaryDirectory() as td:
            app, folder = self.fixture(pathlib.Path(td))
            (folder / "Fixture").write_bytes(b"\xcf\xfa\xed\xfe")
            self.assertEqual(scan_bundle(app)["status"], "main-arm64-unverified")

if __name__ == "__main__":
    unittest.main()
