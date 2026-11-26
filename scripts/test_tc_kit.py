"""Check actual source-only kit contents before artifact publication."""
import pathlib, sys, plistlib
from package_tc_local import validate_frameworks
root=pathlib.Path(sys.argv[1])
validate_frameworks(root/"Frameworks")
assert (root/"UPSTREAM-LICENSE.txt").is_file()
assert not (root/"__pycache__").exists()
print("Framework metadata, ARM64 platform and license checks passed")
