#!/usr/bin/env bash
set -euo pipefail
recipe="$(cd "$1" && pwd)"
here="$(cd "$(dirname "$0")" && pwd)"
toolchains="$recipe/toolchains"
mkdir -p "$toolchains"
tarball="$toolchains/mesa-25.0.7.tar.xz"
sha=592272df3cf01e85e7db300c449df5061092574d099da275d19e97ef0510f8a6
if [ ! -f "$tarball" ]; then
  curl --fail --location --retry 3 --output "$tarball" https://archive.mesa3d.org/mesa-25.0.7.tar.xz
fi
echo "$sha  $tarball" | shasum -a 256 -c -
# Test the precise pinned source against the same strict language and iOS
# target that failed, before spending time building MoltenVK.
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
tar -xf "$tarball" -C "$scratch" mesa-25.0.7/src/util/u_endian.h
src="$scratch/mesa-25.0.7"
patch -d "$src" -p1 --dry-run < "$here/0010-apple-target-endian.patch"
patch -d "$src" -p1 < "$here/0010-apple-target-endian.patch"
cat > "$scratch/check.c" <<'EOF'
#include "util/u_endian.h"
#if UTIL_ARCH_LITTLE_ENDIAN != 1 || UTIL_ARCH_BIG_ENDIAN != 0
#error Incorrect iOS ARM64 byte order
#endif
int main(void) { return 0; }
EOF
for mode in c c++; do
  if [ "$mode" = c ]; then std=c11; else std=c++17; fi
  xcrun --sdk iphoneos clang -target arm64-apple-ios17.0 -x "$mode" -std="$std" \
    -DHAVE_ENDIAN_H -Wall -Wextra -Werror -fsyntax-only -I"$src/src" "$scratch/check.c"
done
# The original BCD script applies and records patches in numeric order.
# Keep it unmodified; append our small MIT-source fix to the disposable copy.
target="$recipe/build/mesa-ios/patches/0010-apple-target-endian.patch"
test ! -e "$target"
cp "$here/0010-apple-target-endian.patch" "$target"
echo "Pinned Mesa iOS endian preflight passed in C11 and C++17."
