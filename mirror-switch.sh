#!/bin/bash
# mirror-switch.sh
# Runs uxplay and auto-switches between MagicMirror (Chromium) and AirPlay.
# Polls for active connections to uxplay to detect AirPlay connect/disconnect.

export DISPLAY=:0

LOG_FILE="/tmp/mirror-switch.log"
POLL_INTERVAL=2
AIRPLAY_ACTIVE=false

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Show MagicMirror (unfreeze Chromium and bring to front)
show_mm() {
    log "Showing MagicMirror"
    pkill -CONT -f chromium 2>/dev/null
    wmctrl -a "Chromium" 2>/dev/null
}

# Hide MagicMirror (minimize and freeze Chromium to free CPU)
hide_mm() {
    log "Hiding MagicMirror"
    wmctrl -r "Chromium" -b add,hidden 2>/dev/null
    sleep 1
    pkill -STOP -f chromium 2>/dev/null
}

log "Starting mirror-switch — launching uxplay..."

# Start uxplay in the background (-fs for fullscreen)
uxplay -n "Mirror" -fs -reset 0 &
UXPLAY_PID=$!
log "uxplay started (PID: $UXPLAY_PID)"

# Wait for uxplay to initialize
sleep 3

# Poll for active AirPlay connections by checking if uxplay has
# established TCP connections (beyond its listening sockets)
while kill -0 "$UXPLAY_PID" 2>/dev/null; do
    CONNECTIONS=$(ss -tnp 2>/dev/null | grep "uxplay" | grep "ESTAB" | wc -l)

    if [ "$CONNECTIONS" -gt 0 ] && [ "$AIRPLAY_ACTIVE" = false ]; then
        log "AirPlay connected ($CONNECTIONS active connections)"
        AIRPLAY_ACTIVE=true
        hide_mm
    elif [ "$CONNECTIONS" -eq 0 ] && [ "$AIRPLAY_ACTIVE" = true ]; then
        log "AirPlay disconnected"
        AIRPLAY_ACTIVE=false
        show_mm
    fi

    sleep "$POLL_INTERVAL"
done

# If uxplay exits while AirPlay was active, show MagicMirror
if [ "$AIRPLAY_ACTIVE" = true ]; then
    log "uxplay crashed during active session"
    AIRPLAY_ACTIVE=false
    show_mm
fi

log "uxplay exited, restarting..."
exec "$0"
