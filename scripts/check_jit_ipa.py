#!/usr/bin/env python3
"""Validate install metadata in the finished unsigned diagnostic IPA."""
import pathlib
import plistlib
import sys
import zipfile

def validate(path):
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None, "IPA integrity check failed"
        names = set(z.namelist())
        roots = [n for n in names if n.startswith("Payload/") and n.count("/") == 2 and n.endswith(".app/Info.plist")]
        assert len(roots) == 1, "expected exactly one top-level app plist"
        host_path = roots[0]
        root = host_path.removesuffix("Info.plist")
        helper_root = root + "PlugIns/TCJITHelper.appex/"
        host = plistlib.loads(z.read(host_path))
        helper = plistlib.loads(z.read(helper_root + "Info.plist"))
        for label, info, prefix, package_type in (
            ("host", host, root, "APPL"),
            ("helper", helper, helper_root, "XPC!"),
        ):
            for key in ("CFBundleIdentifier", "CFBundleDisplayName", "CFBundleName",
                        "CFBundleExecutable", "CFBundleVersion", "CFBundleShortVersionString",
                        "CFBundlePackageType", "MinimumOSVersion"):
                value = info.get(key)
                assert isinstance(value, str) and value.strip(), f"{label}: missing/empty {key}"
                assert "$(" not in value and "${" not in value, f"{label}: unresolved {key}"
            assert info["CFBundlePackageType"] == package_type, f"{label}: incorrect package type"
            exe = info["CFBundleExecutable"]
            assert "/" not in exe and prefix + exe in names, f"{label}: executable missing"
        assert helper["CFBundleIdentifier"].startswith(host["CFBundleIdentifier"] + ".")
        assert helper["CFBundleVersion"] == host["CFBundleVersion"]
        assert helper["CFBundleShortVersionString"] == host["CFBundleShortVersionString"]
        ext = helper["NSExtension"]
        assert ext["NSExtensionPointIdentifier"] == "com.apple.ar.viewer"
        assert ext["NSExtensionPrincipalClass"] == "TCClassicHelperHandler"
        assert not any(n.endswith(".appexpt") for n in names)
        assert not any(n.endswith("embedded.mobileprovision") for n in names)
        print("Final IPA install metadata verified: host and helper display names, executable paths, versions, package types and identifier prefix")

if __name__ == "__main__":
    validate(pathlib.Path(sys.argv[1]))
