# Changelog

## 0.1.0 (2026-10-06)

First public version.

- `macsim bootstrap` sets up SSH, the Mac-side scripts, a private agent-device + serve-sim install and a LaunchAgent proxy.
- `macsim build` covers Swift/Xcode, XcodeGen, Expo (CNG + dev client) and React Native: `.gitignore`-aware incremental sync, deps/Pods only when lockfiles change, plain `xcodebuild`, install and launch.
- Metro stays on the client, reached through a reverse SSH tunnel (`--metro-port` for non-default ports).
- `ios-device`: agent-device connected to the Mac (SSH tunnel by default, or direct over Tailscale). It auto-targets the macsim simulator, never a paired physical iPhone.
- `macsim view`: live simulator in the browser via serve-sim.
- `macsim install`, `screenshot`, `open-url`, `launch`, `devices`, `boot`, `shutdown`, `list`, `clean`, `uninstall`.
- `macserver` on the Mac: stay awake with the lid closed. Optional `pc` command to SSH back into the client.
- Agent skill `mac-ios`, `install.sh`, offline test suite, CI.

Out of scope for now: physical devices, packaging (Homebrew/npm), macOS as the client machine.
