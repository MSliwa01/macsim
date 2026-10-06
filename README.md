# macsim

[![ci](https://github.com/MSliwa01/macsim/actions/workflows/ci.yml/badge.svg)](https://github.com/MSliwa01/macsim/actions/workflows/ci.yml) [![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

**Use a Mac as a remote iOS build server and iPhone Simulator, so you (and your AI coding agents) can work on iOS apps from Linux.**

Your code, editor and agents stay on your main machine. A Mac on your network (an old MacBook works) compiles the app and runs the Simulator. One command syncs, builds, installs and launches. Agents can tap through the app with [agent-device](https://github.com/callstack/agent-device), and you can watch it live in your browser.

```
your machine (Linux / WSL)                      Mac (reached over SSH)
──────────────────────────                      ──────────────────────
repo, editor, agents, Metro
macsim build ───── rsync + ssh ─────────────▶   ~/.macsim/builds/<project>  (incremental)
                                                xcodebuild → iOS Simulator
ios-device ─────── agent-device proxy ──────▶   tap / type / snapshot / screenshot
Metro :8081 ◀───── reverse SSH tunnel ───────   app in the Simulator (hot reload)
browser ◀───────── serve-sim over SSH ───────   live Simulator view (macsim view)
```

- **Swift / Xcode**, including **XcodeGen** projects (`project.yml`).
- **Expo** (dev client, prebuild/CNG, Expo Go) and **React Native**, with Metro running on *your* machine.
- **Agent-ready:** ships an [agent skill](skill/mac-ios/SKILL.md) for Claude Code, Codex and other tools that read `SKILL.md`. Build errors come back trimmed to what matters.
- **Small-Mac friendly:** incremental builds, `.gitignore`-aware sync, one booted simulator, and commands to prune caches.

> Status: early (v0.1). Used daily on one setup (see [Tested on](#tested-on)). Issues and PRs are welcome.

## Requirements

| | Mac | Your machine |
|---|---|---|
| OS | macOS with Xcode installed. Apple Silicon recommended (`macsim view` needs it; everything else also works on Intel) | Linux or WSL2 (macOS as a client is untested) |
| Tools | Xcode + one iOS Simulator runtime, Node ≥ 20 (`setup.sh` finds or offers to install it), optional CocoaPods (RN/Expo) and XcodeGen | `bash` ≥ 4, `ssh`, `rsync`, `curl`, `node` ≥ 20, [`agent-device`](https://www.npmjs.com/package/agent-device) for UI automation, `tmux` (only for `--pc-access`) |
| Access | **Remote Login** enabled (System Settings → General → Sharing), a **logged-in user session** | SSH reachability to the Mac (LAN, Tailscale, any VPN) |
| Disk | ~30–40 GB for Xcode + runtime, plus **1–8 GB per project** (see [Disk usage](#disk-usage)) | n/a |

## Quick start

```bash
# 1. On your machine
git clone https://github.com/MSliwa01/macsim && cd macsim
./install.sh --skill              # links macsim + ios-device into ~/.local/bin, installs the agent skill
npm i -g agent-device             # UI automation client (the Mac gets the same version)

# 2. Connect the Mac (interactive: asks for the Mac password once, may ask for sudo)
macsim bootstrap <mac-user>@<mac-host>

# 3. Check, then build something
macsim status
cd ~/code/my-app && macsim build
macsim view                       # watch the simulator in your browser
```

`bootstrap` does all of this:

- creates an SSH alias (`macsim-mac`) and copies your SSH key to the Mac;
- uploads the Mac-side scripts to `~/.macsim`;
- runs [`mac/setup.sh`](mac/setup.sh) on the Mac, which checks Xcode and the iOS runtime, finds Node, installs agent-device and serve-sim privately in `~/.macsim/tools`, and starts a LaunchAgent with the agent-device proxy;
- prints the result of `macsim status`.

`macsim bootstrap` flags:

| Flag | Effect |
|---|---|
| `--direct` | Bind the proxy to the Mac's Tailscale address and reach it at `http://<mac-host>:4310` instead of through an SSH tunnel. For another interface, set `PROXY_BIND=<ip>` in `~/.macsim/config` on the Mac. By default the proxy stays on `127.0.0.1` and is reached through SSH. |
| `--pc-access` | Let the Mac SSH back into your machine. Adds a `pc` command on the Mac that attaches to a tmux session where your agents run. Useful when you're on the laptop and the agents live on the desktop. |
| `--alias NAME` | Use a different SSH alias. |

## Everyday use

| Command | What it does |
|---|---|
| `macsim build [PATH]` | Sync, build, install and launch. Auto-detects Expo / React Native / Xcode / XcodeGen. Options: `--device`, `--scheme`, `--configuration`, `--prebuild`, `--no-launch`, `--type`. |
| `macsim status` | Checks reachability, Xcode, runtime, proxy, disk and versions. Every failure line says how to fix it. |
| `macsim tunnel start\|stop` | Makes the Mac's `127.0.0.1:8081` reach Metro on your machine. Use `--metro-port N` for other ports. |
| `macsim dev-client` / `macsim expo-go` | Points an Expo dev client at your Metro / installs the matching Expo Go (experimental). |
| `macsim install FILE --launch` | Installs a simulator `.app` / `.tar.gz` / `.zip`, e.g. an EAS simulator build. |
| `macsim view` | Opens the live simulator in your browser via [serve-sim](https://github.com/EvanBacon/serve-sim) on `localhost:3200`. |
| `macsim screenshot`, `launch`, `open-url`, `devices`, `boot`, `shutdown` | The usual simulator chores. |
| `ios-device …` | `agent-device`, connected to the Mac's simulator. |
| `macsim list` / `macsim clean …` | Shows / prunes per-project caches on the Mac. |
| `macsim ssh [CMD]` | Shell on the Mac with the macsim environment. |

On the Mac:

| Command | What it does |
|---|---|
| `macserver on` | Keeps the Mac awake with the lid closed. Uses `pmset disablesleep`; keep it on the charger. |
| `macserver off` | Restores normal sleep. |
| `macserver status` | Shows the sleep setting and the proxy state. |
| `pc` | Attaches to the tmux session on your machine (needs `--pc-access`). |

Run `macsim help` for everything.

### Expo / React Native workflow

1. Start Metro on your machine: `npx expo start`.
2. Run `macsim build` once. It creates the reverse tunnel when Metro is up, prebuilds (CNG), runs `pod install`, builds with `xcodebuild` and opens the dev client against your Metro.
3. Edit JS: hot reload goes through the tunnel. Rebuild only when native code, native dependencies or config plugins change (`macsim build --prebuild` after plugin changes).

Builds use plain `xcodebuild`, not `expo run:ios`. That avoids AppleScript and window activation (which fail over SSH) and keeps DerivedData inside the project's build dir.

### Agents

Install the skill with `./install.sh --skill`. It links `skill/mac-ios` into `~/.claude/skills` and `~/.agents/skills`. Then ask your agent things like "build this on the iPhone simulator and check the login screen". The skill teaches it to:

- run `macsim status` first and stop if the Mac is asleep;
- build, read trimmed errors and iterate;
- drive the UI with `ios-device open/press/fill/wait/screenshot/close`;
- handle the known iOS dialogs and crashes;
- be careful with the Mac's disk and RAM.

`ios-device open` without `--device`/`--udid` always targets the macsim simulator, so an agent never grabs a physical iPhone that is paired with the Mac.

## How it works

- **Sync:** each project gets `~/.macsim/builds/<name>-<hash>/{src,dd,logs}` on the Mac. `rsync --delete` skips `.git`, `node_modules`, `Pods`, build output, anything in your `.gitignore` files, and anything in an optional `.macsimignore`. Files generated on the Mac (`ios/` from Expo prebuild, `*.xcodeproj` from XcodeGen, `node_modules`, `Pods`) are protected from deletion, so builds stay incremental.
- **Build:** JS deps are reinstalled only when the lockfile changes, Pods only when the Podfile/lockfile changes, and XcodeGen runs with `--use-cache`. Then `xcodebuild` builds against the simulator and the app is installed with `simctl`.
- **UI automation:** a LaunchAgent on the Mac runs `agent-device proxy`, protected by a random token. `ios-device` connects to it through an SSH tunnel (default) or directly (`--direct`), using its own agent-device state dir so a local `agent-device` keeps working.
- **Updates:** the client hashes `mac/` and re-uploads the Mac-side scripts automatically when they change. After `git pull` there's nothing to do on the Mac.

## Disk usage

The Mac needs Xcode plus one iOS runtime (≈30–40 GB) and space for each project's working copy. Measured on a real setup:

| Project | On the Mac |
|---|---|
| Small SwiftUI app (XcodeGen) | 0.2–2 GB |
| SwiftUI app with Firebase (SPM) | ~6.5 GB |
| Expo SDK 5x app (`node_modules` + Pods + DerivedData) | ~7.5–8 GB |

What to run when space gets tight:

- `macsim list` shows cached projects and their size.
- `macsim clean --derived` drops all DerivedData; the next build is a full rebuild.
- `macsim clean --stale 7` removes projects unused for a week.
- `macsim clean NAME` removes one project.

macsim never deletes anything unless you ask.

## Security

- **Proxy:** by default the agent-device proxy listens only on `127.0.0.1` on the Mac and is reached through your SSH connection. With `--direct` it binds to the Mac's Tailscale address (`PROXY_BIND=tailscale`) or any address you set. All proxy requests need a random 32-byte token, stored in `~/.config/macsim/token` (client) and `~/.macsim/token` (Mac), mode 600. Anyone with the token and network access to the proxy can control the simulator.
- **SSH:** macsim uses your normal SSH key auth with `BatchMode`, so it never stores passwords.
- **Files touched outside the repo:**

| Where | Change |
|---|---|
| Your machine | `~/.ssh/config`: one `Host macsim-mac` block marked `# added by macsim` (backup `~/.ssh/config.bak-macsim`) |
| | `~/.ssh/id_ed25519`: created only if you have no SSH key |
| | `~/.ssh/authorized_keys`: the Mac's key, only with `--pc-access` |
| | `~/.config/macsim/`, `~/.cache/macsim/` |
| | the links made by `install.sh` |
| Mac | `~/.macsim/` (scripts, tools, logs, builds) |
| | `~/Library/LaunchAgents/com.macsim.proxy.plist` |
| | one `PATH` line in `~/.zshrc` marked `# macsim` |
| | your public key in `~/.ssh/authorized_keys` (via `ssh-copy-id`) |
| | with `--pc-access`: a `Host pc` block in `~/.ssh/config` and `~/.ssh/id_ed25519` if missing |
| | `pmset disablesleep`, only when you run `macserver on` |

## Uninstall

```bash
macsim uninstall            # Mac: LaunchAgent, ~/.macsim, builds, PATH line, Host pc; here: config, cache, SSH block
macsim uninstall --keep-builds
./install.sh --uninstall    # remove the macsim / ios-device links and the skill
```

Your public key stays in the Mac's `~/.ssh/authorized_keys`. Remove it by hand if you want.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `unreachable` / exit code 3 | The Mac is asleep, offline or logged out. Log in on the Mac (the LaunchAgent and the Simulator need a GUI session; with FileVault the Mac stays "offline" after a reboot until someone logs in). `macserver on` keeps it awake with the lid closed. |
| `FAIL proxy /health` | Look at `~/.macsim/logs/proxy.log` on the Mac, then run `macserver restart`. |
| First `ios-device open` takes 1–2 min | agent-device is building its XCUITest runner on the Mac. This happens once per restart or upgrade. |
| agent-device version warning | Use the same version on both sides: `npm i -g agent-device@X` here, or `bash ~/.macsim/setup.sh --agent-device-version X` on the Mac. |
| "Open in <App>?" dialog | iOS asks the first time a deep link opens a dev client. Tap it, or let the agent press it (see the skill). |
| App closes right after launch | Read the newest crash report in `~/Library/Logs/DiagnosticReports` on the Mac (`macsim ssh 'ls -t ~/Library/Logs/DiagnosticReports \| head'`). On the iOS 27 runtime, apps without UIScene lifecycle crash at launch; older Expo/RN templates are affected. |
| Port 8081 busy | Another Metro is running. Start yours on another port and pass `--metro-port N`. |
| `macsim view` keyboard doesn't type (Xcode 27) | Grant Accessibility to the terminal app that launched serve-sim on the Mac. |

## Limitations

- **Simulator only:** physical devices, SwiftUI Previews, Instruments and the Xcode debugger UI need the Mac itself.
- **Monorepos:** the directory you build is what gets synced, so hoisted `node_modules` above it isn't.
- **SwiftPM-only packages:** a package without an app project can't be launched.
- **Not yet exercised on real setups:** `macsim expo-go` and bare React Native (non-Expo) builds.

## Tested on

- **Mac:** MacBook Air M1, 8 GB, macOS 27.0.1, Xcode 27.0, iOS 27 runtime.
- **Client:** Ubuntu-based Linux, bash 5.2, agent-device 0.20.10.
- **Network:** the Tailscale (`--direct`) proxy mode is used daily. The SSH-tunnel mode (the default for new installs) was verified end to end by hand.

## Development

```bash
tests/run.sh          # offline tests against a fake Mac (sync filters, auto-push, clean, uninstall)
tests/mac-compat.sh   # mac/ must stay BSD userland + /bin/bash 3.2 compatible
shellcheck install.sh bin/* mac/setup.sh mac/bin/* tests/*.sh
```

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits

Built on [agent-device](https://github.com/callstack/agent-device) (Callstack) for UI automation and [serve-sim](https://github.com/EvanBacon/serve-sim) (Evan Bacon) for the live preview.

## License

[MIT](LICENSE)
