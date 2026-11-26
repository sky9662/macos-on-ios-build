# Desktop OpenGL backend source and build provenance

This independent iOS ARM64 build uses the exact public recipes from BCD at commit
8c784fe01359ece82158567676948628f5f41099:
https://github.com/thebcd69/bcd-games/tree/8c784fe01359ece82158567676948628f5f41099/build

- Mesa 25.0.7 source: https://archive.mesa3d.org/mesa-25.0.7.tar.xz
  SHA256: 592272df3cf01e85e7db300c449df5061092574d099da275d19e97ef0510f8a6 .
  MIT and component-specific notices, with iOS patches from the pinned recipe.
- MoltenVK v1.4.2: https://github.com/KhronosGroup/MoltenVK/tree/db66022459ffb663aa2b50f6b018bc2e124f5edf .
  Apache-2.0, with upstream dependency sources and notices.
- BCD/Madeira build scripts are executed from the pinned upstream checkout, and
  accompanying GPL notices and the original MIT Mesa patches are preserved
  alongside build outputs. No BCD application, Wine, or game binaries included.
- Sources and build instructions for the corresponding libraries are available
  from the above fixed sources and original scripts. The artifact carries copies
  of recipes, patches, third-party notices, version files and binary SHA256s.

Phase 1: cross-compile the libraries, verify ARM64/iOS platform, exported
OSMesa/Vulkan APIs and link an independent compile-only consumer. This is not
runtime validation. Phase 2: implement NSOpenGLContext / desktop symbol
resolution and Metal presentation using OSMesa; then validate a real shader
draw/read on device. Preserve the existing GLES backend as a fallback.
No change to game JIT, security, or packaging gates.

## Round 44 failure / round 45 correction
Run 45797917173: MoltenVK succeeded; Mesa ninja stopped at 474/928 compiling generated program_lex.yy.c. The compiler invocation included -std=c11, -DHAVE_ENDIAN_H, iPhoneOS27.1.sdk and arm64. Mesa 25.0.7 src/util/u_endian.h line 93 rejected unset UTIL_ARCH_LITTLE_ENDIAN / UTIL_ARCH_BIG_ENDIAN. The header prioritizes HAVE_ENDIAN_H over the Apple branch and only tests legacy aliases there. Fix: prefer Clang target byte-order macros on Apple targets, retaining the existing generic/Apple fallbacks and final consistency check. No hardcoded architecture override or weakened warning flags. Download and SHA256-check the pinned tarball early; dry-run/apply the patch to the exact header and compile the strict C11/C++17 regression with HAVE_ENDIAN_H before building MoltenVK. Then copy the patch into the disposable BCD recipe's existing numbered patch series, retaining it with the build's source recipes. No change to upstream repositories or existing GLES/JIT workflow. Actual successful full Mesa build remains unverified.
Reference header: https://github.com/chaotic-cx/mesa-mirror/blob/mesa-25.0.7/src/util/u_endian.h

## Round 45 success / round 46 Mac context adapter
Run 45802030168 succeeded all steps. Artifact 15107443276 (5346525 bytes) contains verified ARM64 iOS Mesa/Zink/MoltenVK libraries and corresponding recipes/notices. Reuse that exact run's artifact (seven-day retention; rebuild and repin when expired), verify SHA256SUMS, package Mesa as OpenGLShim.framework and MoltenVK as MoltenVK.framework, link the independently implemented AppKit context to Mesa instead of OpenGLES. Build the real macOS ARM64 toy application against desktop OpenGL, retag it and verify all its direct GL imports are exported by Mesa. Device diagnostic tests real renderer name (Zink), CFBundle lookup, GLSL 150 and 410, samplerBuffer, base-vertex, buffer update and polygon mode, OSMesa BGRA readback and synchronous Metal blit. Context and presentation are main-thread-only, limited core pixel-format request, single-buffered FRONT selection; resize and general game format/CGL/GL_BACK compatibility, sharing, orientation and performance require further validation. No game or JIT modifications. GLES remains separately buildable. No claim of runtime success until physical-device test. The normal Mesa build workflow is restricted to library recipe inputs so context-only changes don't repeat the expensive dependency build.
