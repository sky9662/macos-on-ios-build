#!/usr/bin/env python3
"""Repository-specific XcodeGen YAML shape check before CI downloads.

This is not a general YAML parser. Require consistent two-space indentation
and the exact sections used by the checked-in project; XcodeGen remains the
authoritative parser.
"""
from pathlib import Path
import sys

def validate(text):
    lines = text.splitlines()
    for n, line in enumerate(lines, 1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        prefix = line[:len(line) - len(line.lstrip())]
        if "\t" in prefix or len(prefix) % 2:
            raise ValueError(f"project.yml:{n}: inconsistent two-space indentation")
    required = ["targets:", "  TCJITHost:", "    info:", "      path: HostInfo.plist",
                "  TCJITHelper:", "schemes:"]
    pos = -1
    for marker in required:
        try:
            pos = lines.index(marker, pos + 1)
        except ValueError as e:
            raise ValueError(f"project.yml: missing or misplaced {marker!r}") from e
    if lines.count("    info:") != 2 or "    type: app-extension" not in lines:
        raise ValueError("project.yml: expected host and classic app-extension info sections")

if __name__ == "__main__":
    try:
        validate(Path(sys.argv[1]).read_text(encoding="utf-8"))
    except (ValueError, OSError) as e:
        sys.exit(str(e))
    print("XcodeGen project indentation and section preflight passed")
