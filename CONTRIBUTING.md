# Contributing

Thanks for helping! macsim is a small bash tool. Keep it that way: no build step, no runtime dependencies beyond the ones listed in the README.

## Layout

| Path | What |
|---|---|
| `bin/macsim` | client CLI (bash ≥ 4, Linux/WSL) |
| `bin/ios-device` | agent-device wrapper |
| `mac/setup.sh`, `mac/bin/*` | Mac side; uploaded to `~/.macsim` automatically when they change |
| `skill/mac-ios/SKILL.md` | agent skill |
| `tests/` | offline tests + Mac compatibility lint |

## Rules of thumb

- **Mac-side code runs on macOS `/bin/bash` 3.2 with BSD tools.** No associative arrays, `mapfile`, `${x,,}`, `sed -i` without `''`, `stat -c`, `date -r FILE`, etc. Use `node` (always present there) for JSON. `tests/mac-compat.sh` catches the common mistakes.
- **Output is read by agents.** Keep success output short and machine-friendly (`KEY=value` lines), and failures specific with a next step.
- **Never delete user data implicitly.** Cleanup commands are explicit.
- **Long-running helpers use pidfiles** in `~/.cache/macsim`. Never `pkill -f` a pattern: it can match unrelated processes, including your own shell.
- Anything that changes files outside the repo must be listed in the README "Security" table and undone by `macsim uninstall`.

## Before opening a PR

```bash
shellcheck install.sh bin/* mac/setup.sh mac/bin/* tests/*.sh
tests/mac-compat.sh
tests/run.sh
```

If you touched build or simulator logic, say in the PR what you ran on a real Mac (macOS / Xcode version, project type).
