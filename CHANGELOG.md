# Changelog

## Unreleased

- `macserver status` shows the size of `~/.macsim/builds`, where new installs keep projects, and of `~/builds` if an older install still has it.
- `macsim view` tries `wslview` before `xdg-open`, so under WSL the preview opens in the Windows browser.
- Script messages use plain punctuation instead of em dashes.

Fixes found by end-to-end runs on a real Mac and by review:

- XcodeGen projects that also commit the `.xcodeproj` alternated between passing and failing builds: every sync put the client's project back and `xcodegen --use-cache` kept it. XcodeGen now always regenerates.
- Bare React Native / Expo with a checked-in `ios/`: the Pods `*.xcworkspace` (and `Podfile.lock`) made on the Mac was deleted by the next sync. They are now protected, and a missing workspace re-runs `pod install`.
- `pod install` now also runs when JS dependencies change (new native modules) and no longer runs on every build when the client's `Podfile.lock` is older than the Mac's.
- Expo CNG: `expo prebuild` re-runs when `app.json`/`app.config.*`, `plugins/` or dependencies change, instead of building a stale `ios/`. Prebuild recreates `ios/` even without `--clean`, so macsim compares the new output with the previous one: unchanged native project → the old `ios/` is kept (17 s instead of ~8 min on an M1 Air); changed → the old Pods are reused so `pod install` only applies the difference (~2 min).
- JS deps also reinstall when `patches/`, `.npmrc`, `.yarnrc.yml` or `pnpm-workspace.yaml` change; a missing yarn/pnpm/bun on the Mac gets a clear message.
- `ios-device reconnect` released nothing, so the old session kept the simulator and the next `open` failed with `DEVICE_IN_USE`. It now disconnects first and no longer piles up connection files. The token is passed through the environment instead of argv.
- `macsim build --device X` (Expo dev client) opened the Metro link on the default simulator instead of X. Release builds no longer try to open the dev client. `--scheme` reached Expo builds only on the client side.
- `macsim screenshot` returned success when the copy failed and always used whichever simulator was `booted`. It is now one round trip, creates the output directory, and fails properly.
- `macsim install Foo.app/` (trailing slash) uploaded the bundle's contents instead of the bundle.
- `--prebuild` on a non-Expo project and an unknown `--type` are rejected before syncing.
- Commands now exit with 3 (Mac unreachable) where they used to exit 1 (`sync`, `build`, `install`, `view`, `expo-go`, `ios-device`).
- Parallel `ios-device` calls no longer fail when one of them loses the race to open the proxy tunnel. Pid files are checked against the running process, so a reused pid is never killed.
- `tunnel start` and `view` wait until the forward really works instead of sleeping 1.5 s, and `tunnel start` reports a port already taken on the Mac.
- Nested `.gitignore` files are honoured even without one at the project root. `.macsimignore` accepts `!pattern` to sync a gitignored file. `.xcode.env.local` (this machine's node path) is no longer synced.
- A simulator picked by name reuses a booted one instead of booting a second with the same name. `screenshot`/`terminate` use the selected simulator.
- `expo-go` reinstalls Expo Go when the project needs a different SDK.
- Uninstall no longer drops a `Host` block written directly after macsim's block in `~/.ssh/config`; setup ends the `Host pc` block with a blank line. `clean --stale` also prunes old uploads and Expo Go downloads.

- React Native / Expo with a checked-in `ios/` made without `pod install` (e.g. prebuilt on Linux): every sync put back the plain `project.pbxproj` and deleted what pod install had added (`PrivacyInfo.xcprivacy`), so every second build failed. macsim now remembers pod install's changes and restores them while the client's files are unchanged.
- `macsim expo-go` could not install current Expo Go releases (the archive holds the bundle contents, and the extracted directory wasn't named `*.app`).
- Editing or updating `macsim` while it runs no longer crashes the running command at the end.
- An interrupted Expo prebuild no longer loses the previous `ios/` and its Pods.
- The simulator window is opened only when macsim boots the simulator, not on every command.

New:

- `macsim log [build|deps|pods|prebuild|xcodegen]` prints the full Mac-side log of the project in the current directory.
- `macsim clean --caches` empties npm/CocoaPods/SwiftPM/yarn/pnpm/bun download caches on the Mac; `macsim status` warns under 10 GB free.
- Builds are serialized on the Mac (`lockf`), so parallel agents don't make a small Mac swap.

Faster:

- SSH commands share one multiplexed connection even without a `ControlMaster` entry in `~/.ssh/config` (~0.15 s per remote call); a short keepalive drops it quickly when the Mac sleeps.
- A no-change rebuild of a small Swift app went from ~8.3 s to ~2.7 s: the scheme is cached (or read from the shared scheme) instead of `xcodebuild -list`, and an unchanged app is not reinstalled.
- `xcodebuild` gets `-skipMacroValidation -skipPackagePluginValidation` (SwiftPM macros and plugins fail headless otherwise) and `-hideShellScriptEnvironment`.
- Build errors show project-relative paths (`App/View.swift:12:5: error: …`) that match your checkout.

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
