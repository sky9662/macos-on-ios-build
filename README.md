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

TC Mesa retains the TC Diagnostics application bundle identifier `com.sky9662.tcdiagnostics` so renderer upgrades can replace the existing diagnostic when signed with the same identity and signing-tool configuration. Earlier Mesa releases used `com.sky9662.tcmesadiagnostics` and may be treated as separate apps. The Mesa build checks the final IPA identifier; framework identifiers remain unchanged.
