#!/usr/bin/env python3
"""Apply the pinned upstream probe's missing explicit framework dependency."""
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
old = "-framework Foundation ../shim/overrides/AppKit.m"
new = "-framework Foundation -framework GameController ../shim/overrides/AppKit.m"
if source.count(old) == 1 and source.count(new) == 0:
    path.write_text(source.replace(old, new, 1))
elif source.count(old) == 0 and source.count(new) == 1:
    pass
else:
    raise SystemExit("Unexpected upstream probe build command; inspect before patching")
print("Verified explicit GameController link in upstream probe")
