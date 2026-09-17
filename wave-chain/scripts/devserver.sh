#!/usr/bin/env bash
#
# The shared dev server, found and reaped portably.
#
# The skill's rule is one dev server for the whole chain. Finding out whether
# one is already up was `lsof -ti:3000`, which does not exist on Windows, so a
# session there either starts a second server or fails to reap the first. This
# wraps the question instead: `lsof` where it exists, `netstat` where it does
# not, same output either way.
#
#   devserver.sh pid          -> PID listening on the port, or nothing
#   devserver.sh start <dir>  -> start `npm run dev` in <dir> only if nothing answers
#   devserver.sh reap         -> kill whatever holds the port

set -uo pipefail
PORT="${WAVE_DEV_PORT:-3000}"

port_pid() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -ti:"$PORT" 2>/dev/null | head -n1
  else
    # Windows: "  TCP  0.0.0.0:3000  0.0.0.0:0  LISTENING  12345"
    # Anchor on ":<port> " so :30000 never matches :3000.
    netstat -ano 2>/dev/null \
      | grep -E "[:.]${PORT}[[:space:]]" \
      | grep -i "LISTEN" \
      | awk '{print $NF}' \
      | grep -E '^[0-9]+$' \
      | head -n1
  fi
}

case "${1:-pid}" in
  pid)
    port_pid
    ;;
  start)
    dir="${2:-.}"
    pid=$(port_pid)
    if [[ -n "$pid" ]]; then
      echo "$pid"
      exit 0
    fi
    ( cd "$dir" && npm run dev >/dev/null 2>&1 & )
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      sleep 1
      pid=$(port_pid)
      [[ -n "$pid" ]] && { echo "$pid"; exit 0; }
    done
    echo "devserver: nothing came up on :$PORT after 10s" >&2
    exit 1
    ;;
  reap)
    pid=$(port_pid)
    if [[ -z "$pid" ]]; then
      echo "devserver: nothing on :$PORT" >&2
      exit 0
    fi
    if command -v taskkill >/dev/null 2>&1 && ! command -v lsof >/dev/null 2>&1; then
      taskkill //F //T //PID "$pid" >/dev/null 2>&1 || taskkill /F /T /PID "$pid" >/dev/null 2>&1
    else
      kill "$pid" 2>/dev/null
    fi
    echo "devserver: reaped $pid on :$PORT"
    ;;
  *)
    echo "usage: devserver.sh [pid|start <dir>|reap]" >&2
    exit 2
    ;;
esac
