#!/usr/bin/env bash
# shellcheck disable=SC2016  # stub bodies and rc-file lines are literal on purpose
# Offline tests for the client <-> Mac plumbing. The "Mac" is a temp HOME on this machine:
# a fake `ssh` runs the remote command locally, so rsync, script auto-push, project prep,
# sync filters, clean and uninstall run for real. Nothing here needs a Mac or Xcode.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/mac" "$T/client/.ssh" "$T/cfg/macsim"

cat >"$T/bin/ssh" <<'SH'
#!/usr/bin/env bash
# fake ssh: drop options and the host, run the command in the fake Mac HOME
while [ $# -gt 0 ]; do case "$1" in -O) exit 0 ;; -o|-i|-p|-R|-L|-S|-F) shift 2 ;; -*) shift ;; *) break ;; esac; done
shift
cd "$FAKE_MAC" && HOME="$FAKE_MAC" PATH="$FAKE_BIN:$PATH" exec bash -c "$*"
SH
# macOS-only tools used by the paths under test
printf '#!/bin/sh\nexit 0\n' >"$T/bin/launchctl"; cp "$T/bin/launchctl" "$T/bin/xcrun"
cat >"$T/bin/sed" <<'SH'
#!/usr/bin/env bash
# accept BSD `sed -i ''` on GNU sed
a=(); while [ $# -gt 0 ]; do if [ "$1" = -i ] && [ "${2-x}" = "" ]; then a+=(-i); shift 2; else a+=("$1"); shift; fi; done
exec /usr/bin/sed "${a[@]}"
SH
chmod +x "$T/bin/"*

export FAKE_MAC="$T/mac" FAKE_BIN="$T/bin" PATH="$T/bin:$PATH" HOME="$T/client"
export XDG_CONFIG_HOME="$T/cfg" XDG_CACHE_HOME="$T/cache"
printf 'MAC_SSH=testmac\nMAC_HOST=fake\nMAC_USER=me\nPROXY_MODE=ssh\n' >"$T/cfg/macsim/config"
M="$ROOT/bin/macsim"

pass=0 fail=0
ok()   { pass=$((pass+1)); echo "ok   $*"; }
bad()  { fail=$((fail+1)); echo "FAIL $*"; }
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }

# ---- fixtures
mkp() { mkdir -p "$T/p/$1"; echo "$T/p/$1"; }
cng="$(mkp cng)"; echo '{"dependencies":{"expo":"~54.0.0","expo-dev-client":"1"}}' >"$cng/package.json"
mkdir -p "$cng/src" "$cng/node_modules/x" "$cng/.git" "$cng/artifacts"; echo a >"$cng/src/App.tsx"
printf 'node_modules/\nartifacts/\n*.log\n' >"$cng/.gitignore"; echo big >"$cng/artifacts/blob"; echo l >"$cng/debug.log"
bare="$(mkp bare)"; echo '{"dependencies":{"react-native":"0.80"}}' >"$bare/package.json"
mkdir -p "$bare/ios/Pods" "$bare/ios/build" "$bare/android"; echo p >"$bare/ios/Podfile"; echo s >"$bare/ios/App.swift"
xg="$(mkp xcodegen)"; mkdir -p "$xg/Sources"; echo 'name: App' >"$xg/project.yml"; echo s >"$xg/Sources/A.swift"
swift="$(mkp swift)"; mkdir -p "$swift/App.xcodeproj"

# ---- project type detection
src_fn() { sed -n "/^$1()/,/^}/p" "$M"; }
eval "$(src_fn has_dep)"; eval "$(src_fn proj_type)"; die() { echo "$*"; return 1; }
check "type: expo"     test "$(proj_type "$cng")" = expo
check "type: rn"       test "$(proj_type "$bare")" = rn
check "type: xcodegen" test "$(proj_type "$xg")" = xcode
check "type: xcode"    test "$(proj_type "$swift")" = xcode

# ---- sync (also exercises script auto-push and `prepare`)
n="$("$M" sync "$cng" 2>/dev/null)"; s="$FAKE_MAC/.macsim/builds/$n/src"
check "scripts pushed to the Mac"         test -x "$FAKE_MAC/.macsim/bin/macsim-remote"
check "fresh install uses ~/.macsim/builds" test -f "$s/src/App.tsx"
check "excludes node_modules"             test ! -e "$s/node_modules"
check "excludes .git"                     test ! -e "$s/.git"
check "honours .gitignore (dir)"          test ! -e "$s/artifacts"
check "honours .gitignore (glob)"         test ! -e "$s/debug.log"
mkdir -p "$s/ios/Pods" "$s/node_modules/y"
"$M" sync "$cng" >/dev/null 2>&1
check "CNG: Mac-generated ios/ survives resync" test -d "$s/ios/Pods"
check "Mac-side node_modules survives resync"   test -d "$s/node_modules/y"
rm "$cng/src/App.tsx"; "$M" sync "$cng" >/dev/null 2>&1
check "deleted files are removed on the Mac"     test ! -e "$s/src/App.tsx"

n2="$("$M" sync "$bare" 2>/dev/null)"; s2="$FAKE_MAC/.macsim/builds/$n2/src"
check "bare RN: ios sources synced"   test -f "$s2/ios/App.swift"
check "bare RN: Pods excluded"        test ! -e "$s2/ios/Pods"
check "bare RN: ios/build excluded"   test ! -e "$s2/ios/build"
check "android/ excluded"             test ! -e "$s2/android"

n3="$("$M" sync "$xg" 2>/dev/null)"; s3="$FAKE_MAC/.macsim/builds/$n3/src"
mkdir -p "$s3/App.xcodeproj"; "$M" sync "$xg" >/dev/null 2>&1
check "XcodeGen: generated .xcodeproj survives resync" test -d "$s3/App.xcodeproj"

echo n >"$bare/ios/New.swift"
check "dry run lists pending changes"   bash -c "'$M' sync '$bare' --dry-run 2>/dev/null | grep -q 'ios/New.swift'"
check "dry run does not copy"           test ! -e "$s2/ios/New.swift"
check "project names are stable" test "$("$M" sync "$cng" 2>/dev/null)" = "$n"
echo 'export NODE_BINARY=/home/me/.nvm/node' >"$bare/ios/.xcode.env.local"; "$M" sync "$bare" >/dev/null 2>&1
check "client .xcode.env.local is not synced"   test ! -e "$s2/ios/.xcode.env.local"
check "bad --type is rejected before syncing"   bash -c "'$M' build '$swift' --type bogus 2>&1 | grep -q 'unknown --type bogus'"
check "--prebuild is rejected for non-Expo"     bash -c "'$M' build '$swift' --prebuild 2>&1 | grep -q 'prebuild is for Expo'"
# bare RN made on Linux: no workspace / Podfile.lock here, so the Mac's must survive a resync
mkdir -p "$s2/ios/App.xcworkspace"; echo L >"$s2/ios/Podfile.lock"; "$M" sync "$bare" >/dev/null 2>&1
check "Pods workspace made on the Mac survives resync" test -d "$s2/ios/App.xcworkspace"
check "Podfile.lock made on the Mac survives resync"   test -f "$s2/ios/Podfile.lock"
# nested .gitignore without a root one; "!pattern" in .macsimignore brings back a gitignored file
mkdir -p "$swift/Sub/junk"; echo j >"$swift/Sub/junk/x"; echo g >"$swift/Sub/GoogleService-Info.plist"
printf 'junk/\nGoogleService-Info.plist\n' >"$swift/Sub/.gitignore"
printf '# comment\n!GoogleService-Info.plist\nextra.txt\n' >"$swift/.macsimignore"; echo e >"$swift/extra.txt"
n5="$("$M" sync "$swift" 2>/dev/null)"; s5="$FAKE_MAC/.macsim/builds/$n5/src"
check "nested .gitignore honoured without a root one"    test ! -e "$s5/Sub/junk"
check ".macsimignore '!pattern' syncs a gitignored file" test -f "$s5/Sub/GoogleService-Info.plist"
check ".macsimignore pattern excludes"                   test ! -e "$s5/extra.txt"
rm -rf "$swift/Sub" "$swift/.macsimignore" "$swift/extra.txt" "$FAKE_MAC/.macsim/builds/$n5"

# ---- simulator commands (simctl stubbed with one booted iPhone)
stub() { printf '#!/usr/bin/env bash\n%s\n' "$2" >"$T/bin/$1"; chmod +x "$T/bin/$1"; }
stub open 'exit 0'
stub xcrun 'case "$*" in
  "simctl list devices available -j") echo "{\"devices\":{\"com.apple.CoreSimulator.SimRuntime.iOS-27-0\":[
    {\"udid\":\"U2\",\"state\":\"Shutdown\",\"name\":\"iPhone 17\"},{\"udid\":\"U1\",\"state\":\"Booted\",\"name\":\"iPhone 17\"}]}}" ;;
  "simctl io U1 screenshot --type=png "*) printf PNGDATA >"${@: -1}" ;;
  *) exit 1 ;;
esac'
"$M" screenshot "$T/shot.png" >/dev/null 2>&1
check "screenshot: PNG streamed back"            test "$(cat "$T/shot.png" 2>/dev/null)" = PNGDATA
check "screenshot: no temp file left behind"     test -z "$(ls "${TMPDIR:-/tmp}"/macsim-shot.* 2>/dev/null)"
check "device by name prefers the booted one"    test "$("$M" boot 'iPhone 17' 2>/dev/null)" = U1
stub xcrun 'exit 1'
check "screenshot: failure is reported"          bash -c "! '$M' screenshot '$T/bad.png' 2>/dev/null && test ! -e '$T/bad.png'"
printf '#!/bin/sh\nexit 0\n' >"$T/bin/xcrun"

# ---- Mac-side build helpers (sourced from macsim-remote)
R="$ROOT/mac/bin/macsim-remote"
rfn() { sed -n "/^$1()/,/^}/p" "$R"; }
# shellcheck disable=SC2034,SC2329  # LOGDIR/SRC/log/die are used by the eval'd functions
(
  eval "$(rfn summarize_failure)"; eval "$(rfn pods_install)"; eval "$(rfn pods_inputs)"; eval "$(rfn pods_integrated)"; eval "$(rfn pods_stash)"; eval "$(rfn ios_files)"
  log() { :; }; die() { echo "$*" >&2; exit 1; }
  w="$T/podproj"; mkdir -p "$w/ios"; LOGDIR="$w"; SRC="$w"
  printf '/x/src/App/A.swift:3:1: error: boom\n' >"$w/b.log"
  sf="$(SRC=/x/src summarize_failure "$w/b.log" 2>&1)"
  grep -qx 'App/A.swift:3:1: error: boom' <<<"$sf" && echo "ok   build errors use project-relative paths" || echo "FAIL build errors use project-relative paths"
  stub pod 'echo run >>../pod-runs; mkdir -p Pods App.xcworkspace; echo L1 >Podfile.lock; cp Podfile.lock Pods/Manifest.lock'
  echo pf >"$w/ios/Podfile"; echo L0 >"$w/ios/Podfile.lock"; echo D1 >"$w/.macsim-deps"
  pods_install "$w/ios"
  echo L0 >"$w/ios/Podfile.lock"; pods_install "$w/ios"   # client re-synced its older lock
  [ "$(wc -l <"$w/pod-runs")" = 1 ] && echo "ok   pods: stale client Podfile.lock does not re-run pod install" || echo "FAIL pods: stale client Podfile.lock does not re-run pod install"
  cmp -s "$w/ios/Podfile.lock" "$w/ios/Pods/Manifest.lock" && echo "ok   pods: Podfile.lock matches Manifest.lock" || echo "FAIL pods: Podfile.lock matches Manifest.lock"
  echo D2 >"$w/.macsim-deps"; pods_install "$w/ios"          # new native JS dependency
  [ "$(wc -l <"$w/pod-runs")" = 2 ] && echo "ok   pods: JS dependency change re-runs pod install" || echo "FAIL pods: JS dependency change re-runs pod install"
  eval "$(rfn prebuild_output_hash)"
  mkdir -p "$w/pb/A.xcodeproj"; printf 'a = 0123456789ABCDEF01234567 /* x */;\nb = 89ABCDEF0123456789ABCDEF /* y */;\n' >"$w/pb/A.xcodeproj/project.pbxproj"
  h1="$(prebuild_output_hash "$w/pb")"
  printf 'b = 1111111111AAAAAAAAAA2222 /* y */;\na = 3333333333BBBBBBBBBB4444 /* x */;\n' >"$w/pb/A.xcodeproj/project.pbxproj"
  mkdir -p "$w/pb/Pods"; echo x >"$w/pb/Pods/junk"
  [ "$h1" = "$(prebuild_output_hash "$w/pb")" ] && echo "ok   prebuild output: random pbxproj IDs and Pods ignored" || echo "FAIL prebuild output: random pbxproj IDs and Pods ignored"
  echo 'c = 1;' >>"$w/pb/A.xcodeproj/project.pbxproj"
  [ "$h1" != "$(prebuild_output_hash "$w/pb")" ] && echo "ok   prebuild output: a real pbxproj change is noticed" || echo "FAIL prebuild output: a real pbxproj change is noticed"
  rm -rf "$w/ios/App.xcworkspace"; pods_install "$w/ios"
  [ "$(wc -l <"$w/pod-runs")" = 3 ] && echo "ok   pods: missing workspace re-runs pod install" || echo "FAIL pods: missing workspace re-runs pod install"
  # ios/ checked in without Pods integration: pod install integrates, a resync puts the plain one back
  mkdir -p "$w/ios/App.xcodeproj"; echo plain >"$w/ios/App.xcodeproj/project.pbxproj"
  stub pod 'echo run >>../pod-runs; mkdir -p Pods App.xcworkspace; echo L1 >Podfile.lock; cp Podfile.lock Pods/Manifest.lock; echo "baseConfigurationReference = X /* Pods-App.debug.xcconfig */" >App.xcodeproj/project.pbxproj; echo p >PrivacyInfo.xcprivacy'
  pods_install "$w/ios"; echo plain >"$w/ios/App.xcodeproj/project.pbxproj"; pods_install "$w/ios"
  [ "$(wc -l <"$w/pod-runs")" = 4 ] && grep -q Pods-App "$w/ios/App.xcodeproj/project.pbxproj" && echo "ok   pods: synced plain pbxproj gets the integrated one back" || echo "FAIL pods: synced plain pbxproj gets the integrated one back"
  rm "$w/ios/PrivacyInfo.xcprivacy"; pods_install "$w/ios"
  [ "$(wc -l <"$w/pod-runs")" = 4 ] && [ -f "$w/ios/PrivacyInfo.xcprivacy" ] && echo "ok   pods: files pod install created come back after a sync" || echo "FAIL pods: files pod install created come back after a sync"
  echo 'plain+new file' >"$w/ios/App.xcodeproj/project.pbxproj"; pods_install "$w/ios"
  [ "$(wc -l <"$w/pod-runs")" = 5 ] && echo "ok   pods: a changed client pbxproj re-runs pod install" || echo "FAIL pods: a changed client pbxproj re-runs pod install"
) >"$T/helpers.log" 2>&1
pass=$((pass + $(grep -c '^ok' "$T/helpers.log"))); fail=$((fail + $(grep -c '^FAIL' "$T/helpers.log")))
cat "$T/helpers.log"

# ---- clean
"$M" clean "$n2" >/dev/null 2>&1
check "clean NAME removes the project" test ! -d "$FAKE_MAC/.macsim/builds/$n2"
check "clean rejects path-like names" bash -c "! '$M' clean ../x 2>/dev/null"

# ---- legacy layout: existing ~/builds projects keep being used
mkdir -p "$FAKE_MAC/builds/old-1"; touch "$FAKE_MAC/builds/old-1/.last-used"
n4="$("$M" sync "$swift" 2>/dev/null)"
check "legacy ~/builds is kept for old installs" test -d "$FAKE_MAC/builds/$n4/src"
rm -rf "$FAKE_MAC/builds"

# ---- uninstall (both sides)
printf 'Host other\n    HostName x\n\n# added by macsim\nHost testmac\n    HostName fake\nHost glued\n    HostName z\n\nHost after\n    HostName y\n' >"$HOME/.ssh/config"
printf 'Host keep\n    HostName k\n\n# added by macsim\nHost pc\n    HostName 1.2.3.4\n\n' >"$FAKE_MAC/.ssh_config"
mkdir -p "$FAKE_MAC/.ssh"; mv "$FAKE_MAC/.ssh_config" "$FAKE_MAC/.ssh/config"
# shellcheck disable=SC2016  # literal rc-file line
printf 'echo hi\nexport PATH="$HOME/.macsim/bin:$PATH"  # macsim\n' >"$FAKE_MAC/.zshrc"
printf 'ssh-ed25519 AAAA me@laptop\nssh-ed25519 BBBB u@mac-macsim\n' >"$HOME/.ssh/authorized_keys"
"$M" uninstall --yes >/dev/null 2>&1
check "uninstall: ~/.macsim removed on the Mac"   test ! -e "$FAKE_MAC/.macsim"
check "uninstall: Mac PATH line removed"          bash -c "! grep -q macsim '$FAKE_MAC/.zshrc' && grep -q 'echo hi' '$FAKE_MAC/.zshrc'"
check "uninstall: Mac 'Host pc' block removed"    bash -c "! grep -q 'Host pc' '$FAKE_MAC/.ssh/config' && grep -q 'Host keep' '$FAKE_MAC/.ssh/config'"
check "uninstall: client Host block removed"      bash -c "! grep -q testmac '$HOME/.ssh/config' && grep -q 'Host other' '$HOME/.ssh/config' && grep -q 'Host after' '$HOME/.ssh/config' && grep -q 'Host glued' '$HOME/.ssh/config'"
check "uninstall: Mac key removed, others kept"   bash -c "! grep -q mac-macsim '$HOME/.ssh/authorized_keys' && grep -q me@laptop '$HOME/.ssh/authorized_keys'"
check "uninstall: client config removed"          test ! -e "$T/cfg/macsim"

# ---- bootstrap (fresh machine + fresh Mac; Xcode/npm/agent-device stubbed)
rm -rf "$FAKE_MAC" "$T/cfg/macsim" "$T/cache"; mkdir -p "$FAKE_MAC" "$HOME/.ssh"
printf 'Host existing\n    HostName e\n' >"$HOME/.ssh/config"; : >"$HOME/.ssh/authorized_keys"
ssh-keygen -q -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519"
stub ssh-copy-id 'exit 0'
stub scp 'for a; do :; done; src="${@: -2:1}"; dst="${@: -1}"; cp "$src" "$FAKE_MAC/${dst#*:}"'
stub agent-device 'echo 0.20.10'
stub npm 'exit 0'
stub xcode-select 'echo /Applications/Xcode.app/Contents/Developer'
stub xcodebuild 'echo "Xcode 27.0"'
stub xcrun 'echo "iOS 27.0 (24A1) - com.apple.CoreSimulator.SimRuntime.iOS-27-0"'
"$M" bootstrap me@fakemac --alias tm --pc-access </dev/null >"$T/bootstrap.log" 2>&1
mc="$FAKE_MAC/.macsim/config"
check "bootstrap: client config written (ssh mode)" grep -q '^PROXY_MODE=ssh$' "$T/cfg/macsim/config"
check "bootstrap: SSH alias block added"            grep -q '^Host tm$' "$HOME/.ssh/config"
check "bootstrap: existing SSH entries kept"        grep -q '^Host existing$' "$HOME/.ssh/config"
check "bootstrap: token copied to the Mac"          cmp -s "$T/cfg/macsim/token" "$FAKE_MAC/.macsim/token"
check "bootstrap: Mac proxy bound to loopback"      grep -q '^PROXY_BIND=127.0.0.1$' "$mc"
check "bootstrap: Mac builds dir default"           grep -q "^BUILDS=\"$FAKE_MAC/.macsim/builds\"$" "$mc"
check "bootstrap: agent-device version pinned"      grep -q '^AGENT_DEVICE_VERSION=0.20.10$' "$mc"
check "bootstrap: LaunchAgent plist written"        test -f "$FAKE_MAC/Library/LaunchAgents/com.macsim.proxy.plist"
check "bootstrap: Mac PATH line added"              grep -q '# macsim$' "$FAKE_MAC/.zshrc"
check "bootstrap --pc-access: Host pc on the Mac"   grep -q '^Host pc$' "$FAKE_MAC/.ssh/config"
check "bootstrap --pc-access: Mac key authorized"   grep -q 'mac-macsim$' "$HOME/.ssh/authorized_keys"
# re-running setup keeps user edits to the Mac config
sed -i 's/^PROXY_BIND=.*/PROXY_BIND=tailscale/' "$mc"
HOME="$FAKE_MAC" PATH="$FAKE_BIN:$PATH" bash "$FAKE_MAC/.macsim/setup.sh" </dev/null >/dev/null 2>&1
check "setup.sh re-run keeps PROXY_BIND"            grep -q '^PROXY_BIND=tailscale$' "$mc"
[ "$fail" = 0 ] || { echo "--- bootstrap log"; tail -20 "$T/bootstrap.log"; }

echo; echo "$pass passed, $fail failed"
[ "$fail" = 0 ]
