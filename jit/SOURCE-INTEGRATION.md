# JIT source integration boundary

The local read-only audit confirms the same legacy macOS-only JIT API remains unresolved after adding chained-import inspection. No game code or audit files are published here. The current synthetic callback probe is compile-only; it does not establish entitlement availability or device execution.

## Upstream review

- Apple: https://developer.apple.com/documentation/apple-silicon/porting-just-in-time-compilers-to-apple-silicon — the old pthread_jit_write_protect_np API is unavailable on iOS; the callback API requires a different source-level writing contract and applicable authorization.
- BCD pinned interface: https://github.com/thebcd69/bcd-games/blob/8c784fe01359ece82158567676948628f5f41099/app/Madeira/JITAllocator.h — an explicit region allocator interface with separate writing and execution views, designed for its own integrated components. It is not a drop-in implementation of the macOS function. Its GPL-3.0-or-later notices must be respected. No BCD code imported.
- Original MIT Mac compatibility project: https://github.com/zorrobyte/macos-on-ios-public/blob/c2562a333d4de4c08da4ceb4a4f1485bddb84e04/README.md — documents native code support and excludes JIT-dependent games from its demonstrated scope.
- .NET runtime issue: https://github.com/dotnet/runtime/issues/108423 — documents the source-level structural changes needed for callback APIs.

## Acceptance gate

A supported integration must have a documented or developer-provided way to control code emission and memory lifecycle, a valid iOS authorization path, and evidence that both relevant modules use the compatible interface. No no-op symbol shim, fabricated export, security bypass or change to Steam checks. Preserve the current fail-closed packer. Ask the game developer for a supported non-JIT mode, an iOS-compatible build, or a licensed allocator/source integration interface. Do not repeat already-passed Mesa or pairing tests. No new build is warranted for this documentation-only investigation.

## Alternative: non-executable guest-code interpretation

Node 26 iOS port documentation identifies the same missing API but explicitly requires source changes and reports device verification on jailbroken iOS 16.1.1 (Dopamine), so it is not evidence of a supported solution on current stock iOS. See https://github.com/Justintunsday/nodejs26-ios/blob/main/docs/RUNTIME_BUILD.md . Applesauce's Dynarmic fork is a source-level CPU backend adaptation for 32-bit guests, not a native ARM64 macOS allocator adapter. See https://github.com/0xjohnnydev/Applesauce .

UTM SE demonstrates threaded interpretation without host JIT (https://github.com/utmapp/UTM). The iSH ARM64 fork describes same-architecture precompiled threaded instruction handlers (https://github.com/meikis/ish-arm64). These are potential design references, not drop-in libraries or evidence that the commercial game's generated code can be isolated. No code from these projects is imported; review licenses, API isolation, guest memory semantics, ABI, callbacks, performance and completeness before choosing a backend. A pure interpreter must keep guest bytes as non-executable data, use only authorized interfaces, and preserve all licensing and platform checks.

Add a local, read-only control-flow inventory for the five known wrappers: instruction counts, indirect transfers, returns, stores, named API textual order and anonymized direct-caller patterns. This is evidence gathering for whether the generated-code execution boundary is identifiable; not a control-flow graph, a game patch, an interpreter implementation, or a proof of supported integration. Synthetic fixtures exercise the parser; no game content uploaded. Source integration is one option, not a prerequisite for further static research.
