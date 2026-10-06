#!/usr/bin/env bash
# The Mac side runs on macOS /bin/bash 3.2 with BSD userland. Shellcheck can't see that,
# so flag GNU-only flags and bash 4+ features in mac/.
cd "$(dirname "$0")/.." || exit 1
pattern='date -r|stat -c|sed -i [^'"'"']|sort -V|readlink -f|-printf|mapfile|readarray|declare -A|local -A|\$\{[A-Za-z_]+(,,|\^\^)|&>>|\|&'
hits="$(grep -nE "$pattern" mac/setup.sh mac/bin/* | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#')"
if [ -n "$hits" ]; then
  echo "$hits"
  echo "GNU-only or bash 4+ construct found in mac/ (see above)"; exit 1
fi
echo "mac/ looks BSD + bash 3.2 compatible"
