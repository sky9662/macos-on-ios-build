#!/bin/bash
set -euo pipefail
root="$(cd "$1" && pwd)"
out="$2"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
repo="$(cd "$(dirname "$0")/.." && pwd)"
test -f "$root/LICENCE"
test -f "$root/src/aarch64/simulator-aarch64.cc"
flags=(-std=c++17 -O2 -DNDEBUG -DVIXL_INCLUDE_TARGET_A64 -DVIXL_INCLUDE_SIMULATOR_AARCH64 -DVIXL_CODE_BUFFER_MALLOC "-I$root/src")
sources=("$root"/src/*.cc "$root"/src/aarch64/*.cc)
for sdk in macosx iphoneos; do
    if [ "$sdk" = macosx ]; then target=arm64-apple-macos14.0; else target=arm64-apple-ios17.0; fi
    dir="$out/$sdk"
    mkdir -p "$dir"
    objects=()
    for source in "${sources[@]}"; do
        obj="$dir/$(basename "$source" .cc).o"
        test ! -e "$obj"
        xcrun --sdk "$sdk" clang++ -target "$target" "${flags[@]}" -c "$source" -o "$obj"
        objects+=("$obj")
    done
    xcrun --sdk "$sdk" libtool -static -o "$dir/libvixl.a" "${objects[@]}"
    xcrun --sdk "$sdk" clang -target "$target" -std=c11 -O2 -c "$repo/interpreter/arm64_subset.c" -o "$dir/subset.o"
    xcrun --sdk "$sdk" clang++ -target "$target" "${flags[@]}" "$repo/interpreter/vixl_reference.cc" "$dir/subset.o" "$dir/libvixl.a" -o "$dir/reference"
    xcrun lipo -verify_arch arm64 "$dir/reference"
    xcrun vtool -show-build "$dir/reference"
    xcrun nm -u "$dir/reference" > "$dir/imports.txt"
    if grep -E 'pthread_jit_write|MAP_JIT' "$dir/imports.txt"; then exit 1; fi
    # General VM imports may have legitimate non-executable uses. Inventory them
    # for review; absence of imports alone does not prove runtime behavior.
    grep -E 'mmap|mprotect|mach_vm|vm_protect' "$dir/imports.txt" || true
    if [ "$sdk" = macosx ]; then "$dir/reference"; else
        xcrun vtool -show-build "$dir/reference" | grep -i 'platform IOS'
    fi
done
cp "$root/LICENCE" "$out/VIXL-LICENCE"
