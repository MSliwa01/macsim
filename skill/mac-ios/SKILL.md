---
name: mac-ios
description: Build, run and drive iOS apps (Swift/Xcode, XcodeGen, React Native, Expo) on the iOS Simulator of a remote Mac from a machine without Xcode (Linux/WSL), using macsim. Use whenever a task needs an iOS build, an iOS simulator, iOS UI testing/verification, screenshots of an iOS app, or "run it on iPhone". Wraps the `macsim` CLI (sync/build/install on the Mac) and `ios-device` (agent-device routed to the Mac).
---

# mac-ios: iOS Simulator on a remote Mac

This machine holds the code and runs you. A Mac reached over SSH builds and hosts the Simulator. Never try to run Xcode or `simctl` locally. Never use plain `agent-device` for iOS here; use `ios-device`.

## Start

```bash
macsim status
```

Exit code 3 / "unreachable" means the Mac is asleep, offline, or not logged in. Stop and tell the user (they can run `macserver on` on the Mac). Do not retry in a loop. Any `FAIL` line names its fix; report it instead of installing things yourself.

## Build + launch (run in the project dir)

```bash
macsim build                        # auto-detects expo | rn | xcode (incl. XcodeGen); syncs, builds, installs, launches
macsim build --scheme MyApp --configuration Debug --device "<simulator name from macsim devices>"
```

- Success prints `BUNDLE_ID=...` and `PROJECT=...`.
- Failure prints only the compiler errors plus the last 30 log lines. Fix the code and rebuild. The full log stays on the Mac: `macsim ssh cat <BUILDS>/<PROJECT>/logs/build.log`.
- Builds are incremental: the Mac keeps the project's deps, Pods and DerivedData between runs, and only changed files are synced (`.gitignore` is respected).

### Expo / React Native

Metro runs **on this machine**. The simulator reaches it through a reverse SSH tunnel.

1. Start Metro in the background here: `npx expo start` (or `npx react-native start`). Keep it running.
2. `macsim tunnel start`. `macsim build` does this automatically when Metro is up.
3. Pick the native shell:
   - Only Expo SDK modules: `macsim expo-go` installs the matching Expo Go and opens the project. No native build. Experimental.
   - `expo-dev-client` or custom native code: `macsim build` once. Rebuild only when native deps, config plugins, or `ios/` change; use `macsim build --prebuild` after config-plugin changes. Afterwards, `macsim dev-client` reconnects the app to Metro.
   - Prebuilt simulator artifact (e.g. EAS `"ios": {"simulator": true}`): `macsim install build.tar.gz --launch`.
4. JS edits hot-reload by themselves. Do not rebuild for JS-only changes.

Rules for Metro and the tunnel:

- If Metro is not on 8081 (another project already holds that port), pass `--metro-port N` to `macsim build`, `tunnel`, `dev-client`, and `expo-go`.
- If the tunnel reports the port busy **on the Mac**, the user runs Metro there. Ask before doing anything.

## Drive the UI

`ios-device` is `agent-device` connected to the Mac (with its own state dir). Follow the agent-device loop with `ios-device` as the binary and always pass `--platform ios`. `open` without `--device`/`--udid` automatically targets the macsim simulator, never a physical iPhone paired with the Mac.

```bash
ios-device open <BUNDLE_ID> --platform ios --foreground    # returns a snapshot with @refs
ios-device press @e12 --settle
ios-device fill @e7 "test@example.com" --settle
ios-device wait text "Welcome"
ios-device screenshot
ios-device close                                            # always close: releases the device lease
```

- The first `open` after a Mac restart or agent-device upgrade can take 1–2 min while the XCUITest runner builds. It is not a hang.
- Leases expire after 5 idle minutes. "Device busy" means another agent holds it: wait or ask, don't force.
- Parallel agents: each one passes its own `--session <name>` on every command.
- Bare React Native: add `--metro-host 127.0.0.1 --metro-port <port>` to `open`.
- Auth or session errors: run `ios-device reconnect`, then retry once.
- Quick look without a session: `macsim screenshot out.png`. Deep link: `macsim open-url 'myapp://path'`. Relaunch: `macsim launch <BUNDLE_ID>`.
- `macsim view` opens a live preview in the user's browser. Offer it when they want to watch; you still drive the UI with `ios-device`.

### Known situations

- **"Open in <App>?" dialog** on the first deep link into a dev client: `ios-device open com.apple.springboard --platform ios`, then `ios-device snapshot -i`, then press the confirm button. The label is localized, so read it from the snapshot. Reopen the app afterwards.
- **App vanishes right after launch:** read the newest crash report with `macsim ssh 'ls -t ~/Library/Logs/DiagnosticReports | head'`. On the iOS 27 runtime, apps without UIScene lifecycle crash at launch (`...NoSceneLifecycleAdoption`), which hits older Expo/RN templates. That is an app issue; report it.

## Housekeeping (the Mac is shared and often small)

- Keep one simulator booted. When the UI work is done for a while, run `macsim shutdown`.
- `macsim list` shows cached projects and their size. Only prune or clean when the user asks:
  - `macsim clean --stale 7` removes projects unused for 7 days.
  - `macsim clean --derived` drops build caches but keeps the projects.
  - `macsim clean <PROJECT>` removes one project.
- Never install or upgrade Xcode, simulator runtimes, CocoaPods, Node or agent-device yourself. Report what `macsim status` says and let the user act.
