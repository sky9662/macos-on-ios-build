# JIT source integration boundary

The local read-only audit confirms the same legacy macOS-only JIT API remains unresolved after adding chained-import inspection. No game code or audit files are published here. The current synthetic callback probe is compile-only; it does not establish entitlement availability or device execution.

## Upstream review

- Apple: https://developer.apple.com/documentation/apple-silicon/porting-just-in-time-compilers-to-apple-silicon — the old pthread_jit_write_protect_np API is unavailable on iOS; the callback API requires a different source-level writing contract and applicable authorization.
- BCD pinned interface: https://github.com/thebcd69/bcd-games/blob/8c784fe01359ece82158567676948628f5f41099/app/Madeira/JITAllocator.h — an explicit region allocator interface with separate writing and execution views, designed for its own integrated components. It is not a drop-in implementation of the macOS function. Its GPL-3.0-or-later notices must be respected. No BCD code imported.
- Original MIT Mac compatibility project: https://github.com/zorrobyte/macos-on-ios-public/blob/c2562a333d4de4c08da4ceb4a4f1485bddb84e04/README.md — documents native code support and excludes JIT-dependent games from its demonstrated scope.
- .NET runtime issue: https://github.com/dotnet/runtime/issues/108423 — documents the source-level structural changes needed for callback APIs.

## Acceptance gate

A supported integration must have a documented or developer-provided way to control code emission and memory lifecycle, a valid iOS authorization path, and evidence that both relevant modules use the compatible interface. No no-op symbol shim, fabricated export, security bypass or change to Steam checks. Preserve the current fail-closed packer. Ask the game developer for a supported non-JIT mode, an iOS-compatible build, or a licensed allocator/source integration interface. Do not repeat already-passed Mesa or pairing tests. No new build is warranted for this documentation-only investigation.
