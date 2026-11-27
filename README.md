# macOS-on-iOS compatibility builds

Public, source-only build project for independently authored ARM64 iOS compatibility probes and local conversion tools. This is not a distribution of Turing Complete or any other commercial game. The unsigned IPA releases contain diagnostic applications only; signing and any device pairing take place locally. The game allocator is not integrated, and preparation success does not establish JIT execution.

## CI

GitHub-hosted standard `xcode-27`, `windows-latest`, and `ubuntu-latest` runners. Workflows run on main changes or manual dispatch; public diagnostic releases use the repository's built-in GitHub token. No personal access token, game asset, device pairing record, profile, or signing identity is needed or permitted. No private repository checkout or private history is included.

## Third-party components

- [macos-on-ios-public](https://github.com/zorrobyte/macos-on-ios-public/tree/c2562a333d4de4c08da4ceb4a4f1485bddb84e04), pinned MIT-licensed upstream. Its copyright and license are retained in `licenses/Upstream-MIT.txt` and packaged with the relevant diagnostics.
- [StikJIT 2.0.1](https://github.com/StikDebug/StikJIT/tree/2.0.1), MPL-2.0; the unchanged upstream framework is downloaded with a pinned SHA-256. Corresponding source is available at that tag; license in `licenses/StikJIT-MPL-2.0.txt` and the diagnostic IPA.

No blanket license is asserted for the new project code; the third-party licenses continue to apply to their respective components. No BCD source or commercial game content is distributed.

## Releases

Download the direct diagnostic IPA from Releases, then use your own valid signing configuration. This project does not distribute a playable game.

### Diagnostic app identity

TC Mesa uses the stable application bundle identifier `com.sky9662.tcmesadiagnostics`, already registered by existing Mesa testers. Do not change it between releases. The final IPA identifier is checked during CI. The earlier TC Diagnostics app has a separate identifier; framework identifiers remain unchanged.

### Local packaging preflight

Use separate, new IPA and audit report paths outside both input trees. Existing reports are preserved, including after a failed preflight. The source-only fixture tests cover path collisions. Round 53 device rendering passed; game-specific imports and JIT remain unverified.

### Import audit coverage and JIT gate

The local converter checks traditional nlist imports and uncompressed dyld chained import tables (formats 1, 2, 3). Unsupported or malformed chained tables fail closed. This is static analysis, not validation of every chain pointer, dynamic symbol lookup, Steam initialization or runtime execution. A catalog entry cannot authorize the unavailable macOS pthread_jit_write_protect_np API; packaging remains blocked when this import is present. Apple's callback-based JIT requires source-level integration and applicable authorization; the existing independent allocator probe is compile-only. No replacement stub, game binary patch or security bypass is provided.

Format reference: https://github.com/apple-oss-distributions/dyld/blob/main/include/mach-o/fixup-chains.h

### Refreshing the Mesa runtime kit

The dedicated Mesa runtime kit workflow reuses the exact SHA-256 verified archive from run 45829046013 (artifact 15121266496) instead of rebuilding Mesa. It refreshes the local Python tools, runs the synthetic ARM64 packaging fixture with the Mesa frameworks, and publishes a versioned ZIP and checksum to Releases. This is a public download, not an installable game. It does not modify the registered diagnostic bundle identifier. If the pinned artifact expires, a new validated runtime build must be pinned explicitly; no unverified fallback is used.

### JIT integration status

See [JIT source integration boundary](jit/SOURCE-INTEGRATION.md) for the upstream review and remaining developer/API authorization gate. Static audit success is not game execution.
