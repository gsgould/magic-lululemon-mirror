#!/bin/bash
# mirror-switch.sh
# Runs uxplay and auto-switches between MagicMirror (Chromium) and AirPlay.
# Polls for active connections to uxplay to detect AirPlay connect/disconnect.
# Includes watchdog: if uxplay is hung while Chromium is frozen, or if uxplay
# enters an unresponsive state, it force-restarts uxplay.

export DISPLAY=:0

LOG_FILE="/tmp/mirror-switch.log"
POLL_INTERVAL=2
AIRPLAY_ACTIVE=false
# Seconds with no connections while Chromium is frozen before we force-restart uxplay
FROZEN_TIMEOUT=30
IDLE_SINCE=0

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

# Kill uxplay and all its children (GStreamer pipelines)
kill_uxplay() {
    local pid=$1
    pkill -9 -P "$pid" 2>/dev/null
    kill -9 "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
}

# Check if uxplay is actually responsive (not hung)
is_uxplay_responsive() {
    local pid=$1
    local state
    state=$(awk '/^State:/ {print $2}' /proc/"$pid"/status 2>/dev/null)
    if [ "$state" = "D" ]; then
        return 1  # uninterruptible sleep — likely hung
    fi
    return 0
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
    NOW=$(date +%s)

    if [ "$CONNECTIONS" -gt 0 ] && [ "$AIRPLAY_ACTIVE" = false ]; then
        log "AirPlay connected ($CONNECTIONS active connections)"
        AIRPLAY_ACTIVE=true
        IDLE_SINCE=0
        hide_mm
    elif [ "$CONNECTIONS" -eq 0 ] && [ "$AIRPLAY_ACTIVE" = true ]; then
        log "AirPlay disconnected"
        AIRPLAY_ACTIVE=false
        IDLE_SINCE=0
        show_mm
    fi

    # Check if uxplay is in an unresponsive D-state
    if ! is_uxplay_responsive "$UXPLAY_PID"; then
        log "WATCHDOG: uxplay (PID $UXPLAY_PID) is in uninterruptible sleep — killing"
        kill_uxplay "$UXPLAY_PID"
        break
    fi

    # Watchdog: only track idle time when Chromium is frozen (AIRPLAY_ACTIVE=true)
    # and connections have dropped. This catches hung uxplay during an AirPlay session.
    # We do NOT timeout during normal idle (AIRPLAY_ACTIVE=false) — that would kill
    # uxplay every 30s when nobody is using AirPlay.
    if [ "$AIRPLAY_ACTIVE" = true ] && [ "$CONNECTIONS" -eq 0 ]; then
        if [ "$IDLE_SINCE" -eq 0 ]; then
            IDLE_SINCE=$NOW
        fi
        IDLE_DURATION=$(( NOW - IDLE_SINCE ))
        if [ "$IDLE_DURATION" -ge "$FROZEN_TIMEOUT" ]; then
            log "WATCHDOG: Chromium frozen but uxplay idle for ${IDLE_DURATION}s — killing (PID $UXPLAY_PID)"
            kill_uxplay "$UXPLAY_PID"
            break
        fi
    else
        IDLE_SINCE=0
    fi

    sleep "$POLL_INTERVAL"
done

# If uxplay exits while AirPlay was active, show MagicMirror
if [ "$AIRPLAY_ACTIVE" = true ]; then
    log "uxplay crashed/killed during active session — restoring MagicMirror"
    AIRPLAY_ACTIVE=false
    show_mm
fi

log "uxplay exited, restarting in 2 seconds..."
sleep 2
exec "$0"
