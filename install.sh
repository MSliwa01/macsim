#!/usr/bin/env bash
# Install (or remove) the macsim commands on this machine.
#   ./install.sh               link `macsim` and `ios-device` into ~/.local/bin (or $BIN_DIR)
#   ./install.sh --skill       also install the `mac-ios` agent skill (Claude Code, Codex, ...)
#   ./install.sh --uninstall   remove the links and the skill (run `macsim uninstall` first
#                              to clean up the Mac)
# Nothing is copied: the links point into this checkout, so `git pull` updates everything.
set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="${BIN_DIR:-$HOME/.local/bin}"
SKILL_DIRS=("$HOME/.claude/skills" "$HOME/.agents/skills")
skill=0 uninstall=0
for a in "$@"; do case "$a" in
  --skill) skill=1 ;; --uninstall) uninstall=1 ;;
  -h|--help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "unknown option: $a" >&2; exit 1 ;; esac; done

links_here() { [ -L "$1" ] && case "$(readlink "$1")" in "$REPO"/*) return 0 ;; esac; return 1; }

if [ $uninstall = 1 ]; then
  for f in macsim ios-device; do links_here "$BIN_DIR/$f" && rm "$BIN_DIR/$f" && echo "removed $BIN_DIR/$f"; done
  for d in "${SKILL_DIRS[@]}"; do links_here "$d/mac-ios" && rm "$d/mac-ios" && echo "removed $d/mac-ios"; done
  exit 0
fi

mkdir -p "$BIN_DIR"
for f in macsim ios-device; do
  if [ -e "$BIN_DIR/$f" ] && ! links_here "$BIN_DIR/$f"; then echo "skip: $BIN_DIR/$f exists and is not ours"; continue; fi
  ln -sfn "$REPO/bin/$f" "$BIN_DIR/$f" && echo "linked $BIN_DIR/$f"
done
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) echo "note: $BIN_DIR is not on your PATH; add it to your shell profile" ;; esac

if [ $skill = 1 ]; then
  for d in "${SKILL_DIRS[@]}"; do
    [ "$d" = "$HOME/.agents/skills" ] && [ ! -d "$HOME/.agents" ] && continue
    mkdir -p "$d"
    if [ -e "$d/mac-ios" ] && ! links_here "$d/mac-ios"; then echo "skip: $d/mac-ios exists and is not ours"; continue; fi
    ln -sfn "$REPO/skill/mac-ios" "$d/mac-ios" && echo "installed skill: $d/mac-ios"
  done
  cat <<'EOF'

Optional: tell your agents about it globally (e.g. ~/.claude/CLAUDE.md or ~/.codex/AGENTS.md):

  ## iOS / iPhone Simulator
  This machine has no Xcode. iOS builds and the Simulator run on a Mac via macsim.
  For anything iOS (build, run, simulator, UI checks, screenshots) use the `mac-ios` skill
  (`macsim` + `ios-device`). Start with `macsim status`; if the Mac is unreachable, tell
  the user instead of retrying.
EOF
fi

echo
missing=()
for c in ssh rsync curl node; do command -v "$c" >/dev/null || missing+=("$c"); done
[ ${#missing[@]} -eq 0 ] || echo "missing required tools: ${missing[*]}"
command -v agent-device >/dev/null || echo "for UI automation install agent-device: npm i -g agent-device"
echo "next: macsim bootstrap <mac-user>@<mac-host>"
