#!/bin/bash
# mirror-switch.sh
# Runs uxplay and auto-switches between MagicMirror (Chromium) and AirPlay.
# Polls for active connections to uxplay to detect AirPlay connect/disconnect.
# Includes watchdog: if uxplay is hung while Chromium is frozen, or if uxplay
# enters an unresponsive state, it force-restarts uxplay.

export DISPLAY=:0

LOG_FILE="/tmp/mirror-switch.log"
HEALTH_LOG="/boot/firmware/mirror-health.log"
POLL_INTERVAL=2
AIRPLAY_ACTIVE=false
# Seconds with no connections while Chromium is frozen before we force-restart uxplay
FROZEN_TIMEOUT=30
IDLE_SINCE=0
# Health check every 30 polls (~60 seconds)
HEALTH_INTERVAL=30
HEALTH_COUNTER=0
TEMP_WARN=75
MEM_WARN_MB=200
SIGNAL_WARN=-67

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Write a persistent health event to /boot/firmware (survives power loss)
log_health() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    log "HEALTH: $1"
    sudo mount -o remount,rw /boot/firmware 2>/dev/null
    echo "$msg" | sudo tee -a "$HEALTH_LOG" > /dev/null
    # Keep log from growing forever (max 500 lines)
    if [ "$(sudo wc -l < "$HEALTH_LOG" 2>/dev/null)" -gt 500 ]; then
        sudo tail -250 "$HEALTH_LOG" > /tmp/health-trim.tmp
        sudo mv /tmp/health-trim.tmp "$HEALTH_LOG"
    fi
    sudo mount -o remount,ro /boot/firmware 2>/dev/null
}

# Check temperature and memory, log if thresholds exceeded
check_health() {
    local temp_raw mem_avail_kb mem_avail_mb throttled signal_dbm
    temp_raw=$(vcgencmd measure_temp 2>/dev/null | grep -oP '[0-9.]+')
    temp_int=${temp_raw%.*}
    mem_avail_kb=$(awk '/MemAvailable/ {print $2}' /proc/meminfo 2>/dev/null)
    mem_avail_mb=$((mem_avail_kb / 1024))
    throttled=$(vcgencmd get_throttled 2>/dev/null | cut -d= -f2)
    signal_dbm=$(awk 'NR>2 {gsub(/\./,"",$4); print -$4}' /proc/net/wireless 2>/dev/null)

    if [ "${temp_int:-0}" -ge "$TEMP_WARN" ]; then
        log_health "HIGH TEMP: ${temp_raw}C (threshold: ${TEMP_WARN}C) | mem_avail: ${mem_avail_mb}MB | throttled: $throttled | wifi: ${signal_dbm}dBm"
    fi

    if [ "${mem_avail_mb:-9999}" -le "$MEM_WARN_MB" ]; then
        log_health "LOW MEMORY: ${mem_avail_mb}MB available (threshold: ${MEM_WARN_MB}MB) | temp: ${temp_raw}C | throttled: $throttled | wifi: ${signal_dbm}dBm"
    fi

    if [ "$throttled" != "0x0" ] && [ -n "$throttled" ]; then
        log_health "THROTTLED: $throttled | temp: ${temp_raw}C | mem_avail: ${mem_avail_mb}MB | wifi: ${signal_dbm}dBm"
    fi

    if [ -n "$signal_dbm" ] && [ "$signal_dbm" -le "$SIGNAL_WARN" ]; then
        log_health "WEAK WIFI: ${signal_dbm}dBm (threshold: ${SIGNAL_WARN}dBm) | temp: ${temp_raw}C | mem_avail: ${mem_avail_mb}MB"
    fi
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
# Also kills any other uxplay instances to avoid mDNS name conflicts on restart.
kill_uxplay() {
    local pid=$1
    pkill -9 -P "$pid" 2>/dev/null
    kill -9 "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    # Kill any straggler uxplay processes to prevent mDNS name conflict
    pkill -9 uxplay 2>/dev/null
    sleep 1
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

# Ensure no stale uxplay processes (prevents mDNS name conflict)
pkill -9 uxplay 2>/dev/null
sleep 1

# Start uxplay in the background (-fs for fullscreen)
uxplay -n "Mirror" -fs &
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

    # Periodic health check
    HEALTH_COUNTER=$((HEALTH_COUNTER + 1))
    if [ "$HEALTH_COUNTER" -ge "$HEALTH_INTERVAL" ]; then
        HEALTH_COUNTER=0
        check_health
    fi

    sleep "$POLL_INTERVAL"
done

# If uxplay exits while AirPlay was active, show MagicMirror
if [ "$AIRPLAY_ACTIVE" = true ]; then
    log "uxplay crashed/killed during active session — restoring MagicMirror"
    AIRPLAY_ACTIVE=false
    show_mm
fi

log_health "uxplay exited/restarted (was_airplay_active=$AIRPLAY_ACTIVE)"
log "uxplay exited, restarting in 2 seconds..."
sleep 2
exec "$0"
