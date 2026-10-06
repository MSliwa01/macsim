#!/bin/bash
# Started by launchd (com.macsim.proxy). Resolves the bind address (PROXY_BIND in
# ~/.macsim/config), then runs the agent-device proxy. launchd restarts it on exit.
MACSIM_HOME="$HOME/.macsim"
# shellcheck disable=SC1091
. "$MACSIM_HOME/env.sh"
PROXY_PORT=4310
# shellcheck disable=SC1091
[ -f "$MACSIM_HOME/config" ] && . "$MACSIM_HOME/config"

host="$("$MACSIM_HOME/bin/macsim-remote" proxy-host)"
if [ -z "$host" ]; then
  echo "$(date '+%F %T') bind address not available yet (PROXY_BIND=${PROXY_BIND:-tailscale}), retrying" >&2
  sleep 10; exit 1
fi
[ -s "$MACSIM_HOME/token" ] || { echo "missing $MACSIM_HOME/token" >&2; sleep 60; exit 1; }

# The proxy does not respawn its local daemon, so keep the daemon alive while the proxy lives
# (the iOS XCUITest runner still idle-stops on its own, so this costs ~one idle node process).
export AGENT_DEVICE_DAEMON_IDLE_TIMEOUT_MS=0
echo "$(date '+%F %T') starting agent-device proxy on $host:$PROXY_PORT" >&2
exec agent-device proxy --host "$host" --port "$PROXY_PORT" \
  --daemon-auth-token "$(cat "$MACSIM_HOME/token")"
