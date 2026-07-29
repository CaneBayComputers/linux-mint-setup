#!/usr/bin/env bash
# Keep the number of open Chrome windows under control.
#
# Written for customers who click a panel launcher repeatedly and end up with
# dozens of browser windows. Once the count exceeds MAX, the oldest windows are
# closed until it's back at MAX.
#
# Usage:
#   chrome-window-limit.sh              # run forever, poll every INTERVAL
#   chrome-window-limit.sh --once       # single pass, useful for testing
#   MAX=3 chrome-window-limit.sh --once
#
# Requires: wmctrl, xprop

MAX="${MAX:-5}"
INTERVAL="${INTERVAL:-4}"
# wmctrl class column for Chrome (e.g. "google-chrome.Google-chrome")
CLASS_RE="${CLASS_RE:-Google-chrome}"

log() { echo "$(date +'%Y-%m-%d %H:%M:%S') $*"; }

# Window id of the currently focused window, normalised to a decimal int.
active_window_dec() {
  local a
  a=$(xprop -root _NET_ACTIVE_WINDOW 2>/dev/null | grep -oE '0x[0-9a-fA-F]+' | head -1)
  [[ -z "$a" ]] && { echo 0; return; }
  echo $((16#${a#0x}))
}

trim_once() {
  # wmctrl -l reports _NET_CLIENT_LIST, which EWMH defines as initial mapping
  # order -- so this array is oldest-first.
  local wins=()
  mapfile -t wins < <(wmctrl -lx 2>/dev/null | awk -v re="$CLASS_RE" '$3 ~ re {print $1}')

  local count=${#wins[@]}
  (( count <= MAX )) && return 0

  local excess=$(( count - MAX ))
  local active closed=0
  active=$(active_window_dec)

  log "chrome windows: $count (max $MAX) -> closing $excess oldest"

  local w
  for w in "${wins[@]}"; do
    (( closed >= excess )) && break
    # never yank away the window she is currently looking at
    if [[ $((16#${w#0x})) -eq $active ]]; then
      log "  skip $w (focused)"
      continue
    fi
    # -c sends WM_DELETE_WINDOW: a clean close, so Chrome does not record a
    # crash and does not show "Restore pages?" on next launch.
    if wmctrl -i -c "$w" 2>/dev/null; then
      log "  closed $w"
      closed=$(( closed + 1 ))
    fi
  done
}

if [[ "${1:-}" == "--once" ]]; then
  trim_once
  exit 0
fi

# Only one watcher at a time -- autostart can fire again on a second login.
# Taken in loop mode only, so --once still works while the watcher runs.
LOCK="${XDG_RUNTIME_DIR:-/tmp}/chrome-window-limit.lock"
exec 9>"$LOCK"
if ! flock -n 9; then
  log "another watcher is already running; exiting"
  exit 0
fi

log "watcher started (max=$MAX, interval=${INTERVAL}s)"
while true; do
  trim_once
  sleep "$INTERVAL"
done
